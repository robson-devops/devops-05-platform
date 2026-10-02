output "arn_suffix" {
  description = "Sufixo do ARN do ALB, usado nas métricas do CloudWatch"
  value       = aws_lb.main.arn_suffix
}

output "dns_name" {
  description = "DNS do ALB, usado como origem do CloudFront"
  value       = aws_lb.main.dns_name
}

output "security_group_id" {
  description = "Security group do ALB, única origem aceita pelas tasks"
  value       = aws_security_group.main.id
}

output "target_group_arn" {
  description = "Target group onde o serviço ECS registra as tasks"
  value       = aws_lb_target_group.main.arn
}
