output "provider_arn" {
  description = "ARN do provider OIDC do GitHub, usado na trust policy das roles do pipeline"
  value       = var.create_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}
