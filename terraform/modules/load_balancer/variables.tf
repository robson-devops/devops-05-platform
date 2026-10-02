variable "access_log_retention_day" {
  description = "Dias até os logs de acesso do ALB expirarem no S3"
  type        = number
  default     = 7

  validation {
    condition     = var.access_log_retention_day >= 1
    error_message = "A retenção deve ser de ao menos 1 dia."
  }
}

variable "application_port" {
  description = "Porta em que o container escuta"
  type        = number
  default     = 8000

  validation {
    condition     = var.application_port > 1024 && var.application_port < 65536
    error_message = "Use uma porta não privilegiada, entre 1025 e 65535."
  }
}

variable "health_check_path" {
  description = "Rota do health check. A /ready consulta o banco: task sem banco não recebe tráfego"
  type        = string
  default     = "/ready"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "O caminho deve começar com /."
  }
}

variable "name_prefix" {
  description = "Prefixo do nome de todos os recursos do módulo"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.name_prefix))
    error_message = "Use de 3 a 24 caracteres entre letras minúsculas, números e hífen."
  }
}

variable "origin_verify_header" {
  description = "Cabeçalho que só o CloudFront envia. Sem ele o ALB responde 403"
  type = object({
    name  = string
    value = string
  })
  sensitive = true

  validation {
    condition     = length(var.origin_verify_header.value) >= 24
    error_message = "O valor do cabeçalho deve ter ao menos 24 caracteres."
  }
}

variable "subnet_id" {
  description = "Subnets públicas, em ao menos duas AZs"
  type        = list(string)

  validation {
    condition     = length(var.subnet_id) >= 2
    error_message = "O ALB exige subnets em ao menos duas AZs."
  }
}

variable "vpc_cidr" {
  description = "CIDR da VPC, destino da saída do ALB para as tasks"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Informe um CIDR válido."
  }
}

variable "vpc_id" {
  description = "VPC do ALB"
  type        = string
}
