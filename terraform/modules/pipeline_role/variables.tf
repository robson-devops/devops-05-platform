variable "github_repository" {
  description = "Repositório no formato owner/nome autorizado a assumir a role"
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "Use o formato owner/repositorio (ex: robson-devops/devops-05-platform)."
  }
}

variable "name" {
  description = "Nome da role"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do provider OIDC do GitHub"
  type        = string
}

variable "policy_json" {
  description = "Policy inline com as permissões da role"
  type        = string
}

variable "subject_claims" {
  description = "Final do claim sub aceito, ex: ref:refs/heads/main ou environment:prod"
  type        = list(string)

  validation {
    condition     = length(var.subject_claims) > 0 && alltrue([for c in var.subject_claims : can(regex("^(ref:refs/heads/|environment:)", c))])
    error_message = "Cada claim deve começar com ref:refs/heads/ ou environment:."
  }
}
