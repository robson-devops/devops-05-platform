variable "alert_email" {
  description = "E-mail dos alertas de orçamento. Fica no terraform.tfvars, fora do Git"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "Informe um endereço de e-mail válido."
  }
}

variable "aws_region" {
  description = "Região AWS do ambiente"
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Tag (SHA do commit) da imagem usada na criação do serviço. Depois disso quem troca a imagem é o pipeline"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "Use o SHA completo do commit, com 40 caracteres hexadecimais."
  }
}

variable "monthly_budget_usd" {
  description = "Limite mensal do orçamento do ambiente, em dólares"
  type        = number
  default     = 30

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "O limite deve ser maior que zero."
  }
}

variable "project_name" {
  description = "Prefixo dos recursos. Precisa ser o mesmo da camada shared"
  type        = string
  default     = "devops-05"
}
