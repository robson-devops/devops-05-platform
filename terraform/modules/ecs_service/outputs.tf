output "cluster_name" {
  description = "Nome do cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "log_group_name" {
  description = "Log group da aplicação"
  value       = aws_cloudwatch_log_group.app.name
}

output "security_group_id" {
  description = "Security group das tasks, origem liberada no banco"
  value       = aws_security_group.task.id
}

output "service_arn" {
  description = "ARN do serviço ECS, usado pelo agendamento de horário"
  value       = aws_ecs_service.main.id
}

output "service_name" {
  description = "Nome do serviço ECS"
  value       = aws_ecs_service.main.name
}

output "task_definition_family" {
  description = "Família da task definition, atualizada pelo pipeline"
  value       = aws_ecs_task_definition.main.family
}
