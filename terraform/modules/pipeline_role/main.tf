data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # O claim decide quem assume: uma branch (build) ou um GitHub Environment (deploy).
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = local.subject_pattern
    }
  }
}

resource "aws_iam_role" "main" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "main" {
  name   = "${var.name}-permissions"
  role   = aws_iam_role.main.id
  policy = var.policy_json
}
