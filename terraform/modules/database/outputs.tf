output "arn" {
  description = "ARN da instância, usado pelo AWS Backup e pelo agendamento de horário"
  value       = aws_db_instance.main.arn
}

output "database_name" {
  description = "Nome do banco"
  value       = aws_db_instance.main.db_name
}

output "endpoint" {
  description = "Endereço da instância, sem a porta"
  value       = aws_db_instance.main.address
}

output "identifier" {
  description = "Identificador da instância"
  value       = aws_db_instance.main.identifier
}

output "master_user_secret_arn" {
  description = "Secret gerenciado pela AWS com as credenciais. O ECS injeta só a senha"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "master_username" {
  description = "Usuário administrador"
  value       = aws_db_instance.main.username
}

output "port" {
  description = "Porta do PostgreSQL"
  value       = aws_db_instance.main.port
}

output "security_group_id" {
  description = "Security group do banco, para liberar a origem"
  value       = aws_security_group.main.id
}
