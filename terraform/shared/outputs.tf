output "ecr_repository_url" {
  description = "URL do repositório ECR compartilhado pelos ambientes"
  value       = module.ecr.repository_url
}

output "build_role_arn" {
  description = "Role do job de build. Cadastre como secret AWS_BUILD_ROLE_ARN no repositório"
  value       = module.build_role.arn
}

output "deploy_role_arn" {
  description = "Role de deploy de cada ambiente. Cadastre como secret AWS_DEPLOY_ROLE_ARN no GitHub Environment correspondente"
  value       = { for env, role in module.deploy_role : env => role.arn }
}
