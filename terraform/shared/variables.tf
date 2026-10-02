variable "aws_region" {
  description = "Região AWS onde a camada compartilhada é criada"
  type        = string
  default     = "us-east-1"
}

variable "create_oidc_provider" {
  description = "Cria o provider OIDC do GitHub, apagado no destroy. Use false se a conta já tiver um"
  type        = bool
  default     = true
}

variable "environments" {
  description = "Ambientes que recebem deploy, cada um com a sua role e o seu GitHub Environment"
  type        = set(string)
  default     = ["dev", "prod"]

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[a-z]{2,8}$", e))])
    error_message = "Use nomes curtos em minúsculas, como dev e prod."
  }
}

variable "github_repository" {
  description = "Repositório (owner/nome) cujo pipeline assume as roles. Em um fork, troque pelo seu"
  type        = string
  default     = "robson-devops/devops-05-platform"
}

variable "project_name" {
  description = "Prefixo dos recursos. As permissões das roles de deploy são limitadas a ele"
  type        = string
  default     = "devops-05"
}
