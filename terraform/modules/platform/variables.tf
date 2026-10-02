variable "alert_email" {
  description = "E-mail dos alertas de orçamento"
  type        = string
  sensitive   = true
}

variable "availability_zone" {
  description = "AZs usadas pelo ambiente"
  type        = list(string)

  validation {
    condition     = length(var.availability_zone) >= 2
    error_message = "Use ao menos duas AZs."
  }
}

variable "database" {
  description = "Dimensionamento do RDS"
  type = object({
    instance_class = string
    multi_az       = bool
  })
}

variable "enable_backup" {
  description = "Cria o plano diário do AWS Backup para o banco"
  type        = bool
  default     = false
}

variable "enable_office_hours" {
  description = "Desliga aplicação e banco fora do horário comercial"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Nome do ambiente"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Use dev ou prod."
  }
}

variable "image" {
  description = "Imagem inicial da aplicação, com tag ou digest"
  type        = string
}

variable "monthly_budget_usd" {
  description = "Limite mensal do orçamento do ambiente, em dólares"
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "O limite deve ser maior que zero."
  }
}

variable "project_name" {
  description = "Prefixo do projeto"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,16}$", var.project_name))
    error_message = "Use de 3 a 16 caracteres entre letras minúsculas, números e hífen."
  }
}

variable "service" {
  description = "Dimensionamento do serviço ECS"
  type = object({
    desired_count = number
    cpu           = number
    memory        = number
  })
}

variable "single_nat_gateway" {
  description = "Um NAT Gateway para todas as AZs em vez de um por AZ"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR /16 da VPC do ambiente"
  type        = string
}
