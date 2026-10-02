variable "allocated_storage_gb" {
  description = "Armazenamento inicial em GB. O autoscaling de disco vai até o dobro"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage_gb >= 20 && var.allocated_storage_gb <= 1000
    error_message = "Use entre 20 GB (mínimo do gp3 no RDS) e 1000 GB."
  }
}

variable "backup_retention_day" {
  description = "Retenção dos backups automáticos do próprio RDS, que permitem restauração em um ponto no tempo"
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_day >= 1 && var.backup_retention_day <= 35
    error_message = "Use de 1 a 35 dias."
  }
}

variable "database_name" {
  description = "Nome do banco criado na instância"
  type        = string
  default     = "tasksdb"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Comece com letra e use só minúsculas, números e sublinhado."
  }
}

variable "deletion_protection" {
  description = "Impede a exclusão da instância. Falso no laboratório para o destroy funcionar"
  type        = bool
  default     = false
}

variable "engine_version" {
  description = "Versão maior do PostgreSQL. As menores sobem sozinhas"
  type        = string
  default     = "17"

  validation {
    condition     = contains(["16", "17"], var.engine_version)
    error_message = "Versões suportadas pelo módulo: 16 ou 17."
  }
}

variable "instance_class" {
  description = "Classe da instância RDS"
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = startswith(var.instance_class, "db.")
    error_message = "A classe deve começar com db., como db.t4g.micro."
  }
}

variable "log_retention_day" {
  description = "Dias de retenção dos logs do PostgreSQL no CloudWatch"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90], var.log_retention_day)
    error_message = "Use um valor aceito pelo CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60 ou 90."
  }
}

variable "master_username" {
  description = "Usuário administrador. A senha é gerada e rotacionada pela AWS"
  type        = string
  default     = "appadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,15}$", var.master_username))
    error_message = "Use de 3 a 16 caracteres, começando com letra."
  }
}

variable "multi_az" {
  description = "Réplica síncrona em outra AZ com failover automático. Dobra o custo da instância"
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefixo do nome de todos os recursos do módulo"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.name_prefix))
    error_message = "Use de 3 a 24 caracteres entre letras minúsculas, números e hífen."
  }
}

variable "subnet_id" {
  description = "Subnets de dados, em ao menos duas AZs"
  type        = list(string)

  validation {
    condition     = length(var.subnet_id) >= 2
    error_message = "O subnet group do RDS exige subnets em ao menos duas AZs."
  }
}

variable "vpc_id" {
  description = "VPC onde fica o security group do banco"
  type        = string
}
