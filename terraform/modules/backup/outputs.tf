output "role_arn" {
  description = "Role usada pelo backup e pelo teste de restauração"
  value       = aws_iam_role.main.arn
}

output "vault_name" {
  description = "Nome do cofre de backup"
  value       = aws_backup_vault.main.name
}
