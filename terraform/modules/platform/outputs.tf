output "alb_dns_name" {
  description = "DNS do ALB. Acesso direto responde 403"
  value       = module.load_balancer.dns_name
}

output "app_url" {
  description = "Endereço HTTPS da aplicação"
  value       = "https://${module.cdn.domain_name}"
}

output "backup_role_arn" {
  description = "Role do AWS Backup, usada no teste de restauração"
  value       = try(module.backup[0].role_arn, null)
}

output "backup_vault_name" {
  description = "Cofre do AWS Backup"
  value       = try(module.backup[0].vault_name, null)
}

output "cloudfront_distribution_id" {
  description = "ID da distribuição CloudFront"
  value       = module.cdn.distribution_id
}

output "cluster_name" {
  description = "Cluster ECS"
  value       = module.ecs_service.cluster_name
}

output "database_identifier" {
  description = "Identificador da instância RDS"
  value       = module.database.identifier
}

output "log_group_name" {
  description = "Log group da aplicação"
  value       = module.ecs_service.log_group_name
}

output "nat_public_ip" {
  description = "IPs de saída da aplicação"
  value       = module.network.nat_public_ip
}

output "service_name" {
  description = "Serviço ECS"
  value       = module.ecs_service.service_name
}

output "vpc_id" {
  description = "VPC do ambiente"
  value       = module.network.vpc_id
}
