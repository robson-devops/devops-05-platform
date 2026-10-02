output "distribution_id" {
  description = "ID da distribuição CloudFront"
  value       = aws_cloudfront_distribution.main.id
}

output "domain_name" {
  description = "Domínio *.cloudfront.net da aplicação"
  value       = aws_cloudfront_distribution.main.domain_name
}
