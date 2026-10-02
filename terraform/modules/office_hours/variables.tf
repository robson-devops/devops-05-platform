variable "database" {
  description = "Instância RDS ligada antes da aplicação e desligada depois dela"
  type = object({
    identifier = string
    arn        = string
  })
}

variable "desired_count" {
  description = "Quantidade de tasks ao ligar o ambiente"
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 1
    error_message = "Ao ligar, o serviço precisa de ao menos uma task."
  }
}

variable "name_prefix" {
  description = "Prefixo dos agendamentos e da role"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.name_prefix))
    error_message = "Use de 3 a 24 caracteres entre letras minúsculas, números e hífen."
  }
}

variable "service" {
  description = "Serviço ECS ligado e desligado pelo agendamento"
  type = object({
    cluster_name = string
    name         = string
    arn          = string
  })
}

variable "start_hour" {
  description = "Hora de ligar o banco. A aplicação sobe 20 minutos depois"
  type        = number
  default     = 8

  validation {
    condition     = var.start_hour >= 0 && var.start_hour <= 22
    error_message = "Use uma hora entre 0 e 22."
  }
}

variable "stop_hour" {
  description = "Hora de desligar a aplicação. O banco para 10 minutos depois"
  type        = number
  default     = 19

  validation {
    condition     = var.stop_hour >= 1 && var.stop_hour <= 23
    error_message = "Use uma hora entre 1 e 23."
  }
}

variable "timezone" {
  description = "Fuso horário dos agendamentos"
  type        = string
  default     = "America/Sao_Paulo"
}

variable "weekdays" {
  description = "Dias da semana em que o ambiente fica ligado, no formato do cron"
  type        = string
  default     = "MON-FRI"
}
