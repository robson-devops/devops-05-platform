output "arn" {
  description = "ARN da role, cadastrado como secret no repositório"
  value       = aws_iam_role.main.arn
}
