terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  required_version = ">= 1.10.0"

  # bucket and region are passed with -backend-config
  backend "s3" {
    key          = "terraform/bot.tfstate"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "vpn"
    }
  }
}

data "archive_file" "bot" {
  type        = "zip"
  source_file = "${path.module}/../../telegram/handler.py"
  output_path = "${path.module}/.build/bot.zip"
}

resource "random_password" "webhook_secret" {
  length  = 64
  special = false
}

# Lambda

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bot" {
  name               = "${var.function_name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json

  # Created by terraform/bootstrap; the GitHub role may change this role only with the boundary set
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.function_name}-lambda-boundary"
}

resource "aws_iam_role_policy_attachment" "bot_logs" {
  role       = aws_iam_role.bot.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "bot_profiles" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.profile_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.profile_prefix}*"]
    }
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.profile_bucket}/${var.profile_prefix}*"]
  }
}

resource "aws_iam_role_policy" "bot_profiles" {
  name   = "read-vpn-profiles"
  role   = aws_iam_role.bot.id
  policy = data.aws_iam_policy_document.bot_profiles.json
}

locals {
  # "eu.amazon.nova-micro-v1:0" -> "amazon.nova-micro-v1:0"
  bedrock_foundation_model = replace(var.bedrock_model_id, "/^(eu|us|apac|global)\\./", "")
}

# A cross-region inference profile needs access to the profile and to the model in every region it routes to
data "aws_iam_policy_document" "bot_bedrock" {
  statement {
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_model_id}",
      "arn:aws:bedrock:*::foundation-model/${local.bedrock_foundation_model}",
    ]
  }
}

resource "aws_iam_role_policy" "bot_bedrock" {
  count = var.bedrock_model_id == "" ? 0 : 1

  name   = "invoke-bedrock"
  role   = aws_iam_role.bot.id
  policy = data.aws_iam_policy_document.bot_bedrock.json
}

resource "aws_cloudwatch_log_group" "bot" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "bot" {
  function_name    = var.function_name
  role             = aws_iam_role.bot.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.bot.output_path
  source_code_hash = data.archive_file.bot.output_base64sha256
  memory_size      = 128
  # Below the 30 s limit of API Gateway, otherwise Telegram gets a 5xx and retries the update
  timeout = 25

  environment {
    variables = {
      TELEGRAM_TOKEN          = var.telegram_token
      TELEGRAM_WEBHOOK_SECRET = random_password.webhook_secret.result
      ALLOWED_CHAT_IDS        = var.allowed_chat_ids
      GH_TOKEN                = var.github_token
      GH_REPO                 = var.github_repo
      S3_BUCKET               = var.profile_bucket
      S3_PROFILE_PREFIX       = var.profile_prefix
      BEDROCK_MODEL_ID        = var.bedrock_model_id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.bot,
    aws_iam_role_policy_attachment.bot_logs,
  ]
}

# HTTP API for the Telegram webhook

resource "aws_apigatewayv2_api" "bot" {
  name          = var.function_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "bot" {
  api_id                 = aws_apigatewayv2_api.bot.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.bot.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "bot" {
  api_id    = aws_apigatewayv2_api.bot.id
  route_key = "POST /tgbot"
  target    = "integrations/${aws_apigatewayv2_integration.bot.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.bot.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.bot.execution_arn}/*/*/tgbot"
}
