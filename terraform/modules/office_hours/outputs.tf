output "schedule_name" {
  description = "Nomes dos agendamentos criados"
  value       = [for schedule in aws_scheduler_schedule.main : schedule.name]
}
