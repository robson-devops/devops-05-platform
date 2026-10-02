variable "availability_zone" {
  description = "AZs usadas pela VPC. Cada camada de subnet ganha uma subnet por AZ"
  type        = list(string)

  validation {
    condition     = length(var.availability_zone) >= 2 && length(var.availability_zone) <= 3
    error_message = "Use 2 ou 3 AZs: o ALB e o subnet group do RDS exigem ao menos duas."
  }
}

variable "flow_log_retention_day" {
  description = "Dias de retenção dos flow logs no CloudWatch"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90], var.flow_log_retention_day)
    error_message = "Use um valor aceito pelo CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60 ou 90."
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

variable "single_nat_gateway" {
  description = "Um NAT Gateway para todas as AZs (mais barato) em vez de um por AZ (sobrevive à perda de uma AZ)"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR da VPC. Precisa ser /16 para caber o esquema de subnets /24 do módulo"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "Informe um CIDR /16 válido, como 10.50.0.0/16."
  }
}
