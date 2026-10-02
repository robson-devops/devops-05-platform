data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

module "ecr" {
  source = "../modules/ecr"

  name = "${var.project_name}-app"
}

module "github_oidc" {
  source = "../modules/github_oidc"

  create_provider = var.create_oidc_provider
}

# Build: só a main publica imagem, e essa role não faz deploy.
data "aws_iam_policy_document" "build" {
  # GetAuthorizationToken não aceita restrição por recurso.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [module.ecr.repository_arn]
  }
}

module "build_role" {
  source = "../modules/pipeline_role"

  name              = "${var.project_name}-pipeline-build"
  github_repository = var.github_repository
  oidc_provider_arn = module.github_oidc.provider_arn
  subject_claims    = ["ref:refs/heads/main"]
  policy_json       = data.aws_iam_policy_document.build.json
}

# Deploy: uma role por ambiente, assumível só pelo GitHub Environment de mesmo nome.
data "aws_iam_policy_document" "deploy" {
  for_each = var.environments

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Leitura para conferir a assinatura do cosign antes do deploy.
  statement {
    sid = "ReadImage"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [module.ecr.repository_arn]
  }

  # Estas duas APIs não aceitam restrição por recurso.
  statement {
    sid = "TaskDefinitions"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid = "UpdateOwnService"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = ["arn:aws:ecs:${local.region}:${local.account_id}:service/${var.project_name}-${each.key}/*"]
  }

  # Sem a condição de serviço, PassRole permitiria escalar privilégio.
  statement {
    sid       = "PassOwnTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.project_name}-${each.key}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

module "deploy_role" {
  source   = "../modules/pipeline_role"
  for_each = var.environments

  name              = "${var.project_name}-pipeline-${each.key}"
  github_repository = var.github_repository
  oidc_provider_arn = module.github_oidc.provider_arn
  subject_claims    = ["environment:${each.key}"]
  policy_json       = data.aws_iam_policy_document.deploy[each.key].json
}
