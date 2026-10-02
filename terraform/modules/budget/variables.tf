variable "alert_email" {
  description = "E-mail que recebe os alertas de orçamento"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "Informe um endereço de e-mail válido."
  }
}

variable "environment" {
  description = "Valor da tag Environment cujo custo o orçamento acompanha"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Use dev ou prod."
  }
}

variable "monthly_limit_usd" {
  description = "Limite mensal em dólares"
  type        = number

  validation {
    condition     = var.monthly_limit_usd > 0
    error_message = "O limite deve ser maior que zero."
  }
}

variable "name_prefix" {
  description = "Prefixo do nome do orçamento"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.name_prefix))
    error_message = "Use de 3 a 24 caracteres entre letras minúsculas, números e hífen."
  }
}
