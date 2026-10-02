variable "alb_security_group_id" {
  description = "Security group do ALB, única origem aceita pelas tasks"
  type        = string
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

variable "cpu" {
  description = "CPU da task Fargate. 256 equivale a 0,25 vCPU"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "Use 256, 512, 1024, 2048 ou 4096."
  }
}

variable "database" {
  description = "Conexão com o banco. A senha vem do secret, nunca daqui"
  type = object({
    endpoint   = string
    port       = number
    name       = string
    username   = string
    secret_arn = string
  })
}

variable "desired_count" {
  description = "Quantidade de tasks. Duas ou mais se espalham pelas AZs"
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 1 && var.desired_count <= 10
    error_message = "Use de 1 a 10 tasks."
  }
}

variable "environment" {
  description = "Nome do ambiente, exposto pela aplicação em /health"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Use dev ou prod."
  }
}

variable "image" {
  description = "Imagem inicial do container. Os deploys seguintes são feitos pelo pipeline"
  type        = string
}

variable "log_retention_day" {
  description = "Dias de retenção dos logs da aplicação e do Container Insights"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90], var.log_retention_day)
    error_message = "Use um valor aceito pelo CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60 ou 90."
  }
}

variable "memory" {
  description = "Memória da task em MiB, compatível com o valor de cpu"
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 30720
    error_message = "Use de 512 a 30720 MiB."
  }
}

variable "name_prefix" {
  description = "Prefixo do cluster, do serviço, das roles e dos demais recursos"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.name_prefix))
    error_message = "Use de 3 a 24 caracteres entre letras minúsculas, números e hífen."
  }
}

variable "subnet_id" {
  description = "Subnets privadas da aplicação"
  type        = list(string)

  validation {
    condition     = length(var.subnet_id) >= 2
    error_message = "Use subnets em ao menos duas AZs."
  }
}

variable "target_group_arn" {
  description = "Target group do ALB"
  type        = string
}

variable "vpc_id" {
  description = "VPC do security group das tasks"
  type        = string
}
