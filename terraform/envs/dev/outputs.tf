output "alb_dns_name" {
  description = "DNS do ALB. Acesso direto responde 403"
  value       = module.platform.alb_dns_name
}

output "app_url" {
  description = "Endereço HTTPS da aplicação. Cadastre como variável APP_URL no GitHub Environment"
  value       = module.platform.app_url
}

output "backup_role_arn" {
  description = "Role do AWS Backup, usada no teste de restauração"
  value       = module.platform.backup_role_arn
}

output "backup_vault_name" {
  description = "Cofre do AWS Backup"
  value       = module.platform.backup_vault_name
}

output "cloudfront_distribution_id" {
  description = "ID da distribuição CloudFront"
  value       = module.platform.cloudfront_distribution_id
}

output "cluster_name" {
  description = "Cluster ECS"
  value       = module.platform.cluster_name
}

output "database_identifier" {
  description = "Identificador da instância RDS"
  value       = module.platform.database_identifier
}

output "log_group_name" {
  description = "Log group da aplicação"
  value       = module.platform.log_group_name
}

output "nat_public_ip" {
  description = "IPs de saída da aplicação"
  value       = module.platform.nat_public_ip
}

output "service_name" {
  description = "Serviço ECS"
  value       = module.platform.service_name
}

output "vpc_id" {
  description = "VPC do ambiente"
  value       = module.platform.vpc_id
}
