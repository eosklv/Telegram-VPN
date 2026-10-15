variable "region" {
  description = "AWS region for the bot"
  type        = string
}

variable "function_name" {
  description = "Lambda function name, also used for related resources"
  type        = string
  default     = "tg-bot"
}

variable "telegram_token" {
  description = "Telegram bot token"
  type        = string
  sensitive   = true
}

variable "allowed_chat_ids" {
  description = "Comma-separated Telegram chat IDs allowed to talk to the bot"
  type        = string

  validation {
    condition     = can(regex("^-?[0-9]+(,-?[0-9]+)*$", var.allowed_chat_ids))
    error_message = "At least one chat ID is required, otherwise the bot ignores everyone."
  }
}

variable "github_token" {
  description = "GitHub token allowed to dispatch workflows and read runs"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "Repository with the deploy workflow, owner/name"
  type        = string
}

variable "profile_bucket" {
  description = "S3 bucket with VPN client profiles"
  type        = string
}

variable "profile_prefix" {
  description = "Key prefix of VPN client profiles"
  type        = string
  default     = "profiles/"
}

variable "bedrock_model_id" {
  description = "Bedrock model or inference profile that understands free-text messages; auto picks the Amazon Nova Micro profile of the region's geography (eu., us., apac.), none or empty for keywords only"
  type        = string
  default     = "auto"
}

variable "aws_location" {
  description = "Location shown by the bot for AWS servers, empty derives it from the region (eu-north-1 -> Stockholm)"
  type        = string
  default     = ""
}
