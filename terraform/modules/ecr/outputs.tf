output "repository_arn" {
  description = "ARN do repositório ECR, usado nas policies das roles do pipeline"
  value       = aws_ecr_repository.main.arn
}

output "repository_url" {
  description = "URL do repositório ECR, usada no push da imagem e nas task definitions"
  value       = aws_ecr_repository.main.repository_url
}
