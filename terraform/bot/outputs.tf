output "webhook_url" {
  description = "URL to register with Telegram setWebhook"
  value       = "${aws_apigatewayv2_api.bot.api_endpoint}/tgbot"
}

output "webhook_secret" {
  description = "secret_token for Telegram setWebhook"
  value       = random_password.webhook_secret.result
  sensitive   = true
}
