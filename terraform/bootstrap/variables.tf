variable "region" {
  description = "AWS region of the bucket and the VPN stacks"
  type        = string
  default     = "eu-north-1"
}

variable "bucket_name" {
  description = "S3 bucket for Terraform states and VPN client profiles"
  type        = string
  default     = "esklv-vpn-eu-north-1"
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "eosklv"
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
  default     = "Telegram-VPN"
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub repository owner"
  type        = number
  default     = 164239463
}

variable "github_repository_id" {
  description = "Numeric ID of the GitHub repository"
  type        = number
  default     = 772944165
}

variable "github_branch" {
  description = "Branch whose workflows may assume the role"
  type        = string
  default     = "main"
}

variable "bot_function_name" {
  description = "Telegram bot Lambda name, the same as function_name in terraform/bot"
  type        = string
  default     = "tg-bot"
}
