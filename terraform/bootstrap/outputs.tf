output "bucket" {
  description = "S3_BUCKET repository variable"
  value       = aws_s3_bucket.state.id
}

output "github_role_arn" {
  description = "GH_ROLE repository variable"
  value       = aws_iam_role.github.arn
}

output "bot_permissions_boundary_arn" {
  description = "Permissions boundary the bot Lambda role must have"
  value       = aws_iam_policy.bot_boundary.arn
}
