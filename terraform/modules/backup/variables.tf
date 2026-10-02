variable "name_prefix" {
  description = "Prefixo do cofre, do plano e da role"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.name_prefix))
    error_message = "Use de 3 a 24 caracteres entre letras minúsculas, números e hífen."
  }
}

variable "resource_arn" {
  description = "Recursos protegidos pelo plano"
  type        = map(string)

  validation {
    condition     = length(var.resource_arn) > 0
    error_message = "Informe ao menos um recurso."
  }
}

variable "retention_day" {
  description = "Dias de retenção de cada ponto de recuperação"
  type        = number
  default     = 7

  validation {
    condition     = var.retention_day >= 1 && var.retention_day <= 35
    error_message = "Use de 1 a 35 dias."
  }
}

variable "schedule_expression" {
  description = "Horário do backup diário, em cron UTC. O padrão 06:00 UTC é 03:00 em Brasília"
  type        = string
  default     = "cron(0 6 * * ? *)"

  validation {
    condition     = startswith(var.schedule_expression, "cron(")
    error_message = "Use uma expressão cron(...) do AWS Backup."
  }
}
