variable "create_provider" {
  description = "Cria o provider OIDC do GitHub. Use false se a conta já tiver um (ele é único por conta)"
  type        = bool
  default     = true
}
