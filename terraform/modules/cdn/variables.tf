variable "name_prefix" {
  description = "Prefixo usado no comentário da distribuição"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.name_prefix))
    error_message = "Use de 3 a 24 caracteres entre letras minúsculas, números e hífen."
  }
}

variable "origin_domain_name" {
  description = "DNS do ALB de origem"
  type        = string
}

variable "origin_verify_header" {
  description = "Cabeçalho secreto que o CloudFront envia ao ALB"
  type = object({
    name  = string
    value = string
  })
  sensitive = true
}

variable "price_class" {
  description = "Classe de preço: quais regiões de borda atendem os usuários"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "Use PriceClass_100, PriceClass_200 ou PriceClass_All."
  }
}
