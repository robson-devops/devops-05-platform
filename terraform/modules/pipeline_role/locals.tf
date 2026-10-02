locals {
  oidc_host = "token.actions.githubusercontent.com"

  repository_owner = split("/", var.github_repository)[0]
  repository_name  = split("/", var.github_repository)[1]

  # Formato clássico e formato com IDs imutáveis do "sub" emitido pelo GitHub.
  subject_pattern = flatten([
    for claim in var.subject_claims : [
      "repo:${var.github_repository}:${claim}",
      "repo:${local.repository_owner}@*/${local.repository_name}@*:${claim}",
    ]
  ])
}
