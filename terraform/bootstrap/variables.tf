variable "region" {
  description = "AWS region of the bucket, the bot and the VPN server"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket for Terraform states and VPN client profiles, globally unique"
  type        = string
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub repository owner: gh api repos/<owner>/<repo> --jq .owner.id"
  type        = number
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
}

variable "github_repository_id" {
  description = "Numeric ID of the GitHub repository: gh api repos/<owner>/<repo> --jq .id"
  type        = number
}

variable "github_immutable_subject" {
  description = "Whether the repository issues immutable OIDC subjects (repo:<owner>@<owner_id>/<repo>@<repo_id>), the default for repositories created since July 2026"
  type        = bool
  default     = true
}

variable "github_branch" {
  description = "Branch whose workflows may assume the role"
  type        = string
  default     = "main"
}

variable "github_role_name" {
  description = "IAM role assumed by GitHub Actions, the GH_ROLE repository variable"
  type        = string
  default     = "vpn-github-actions"
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider if the account already has one, null creates it"
  type        = string
  default     = null
}

variable "bot_function_name" {
  description = "Telegram bot Lambda name, the same as function_name in terraform/bot"
  type        = string
  default     = "tg-bot"
}

variable "import_existing" {
  description = "Adopt a bucket and a GitHub role created by hand: import them instead of creating, see imports.tf"
  type        = bool
  default     = false
}
