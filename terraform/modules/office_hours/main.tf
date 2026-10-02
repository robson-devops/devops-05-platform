data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "main" {
  name               = "${var.name_prefix}-office-hours"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "main" {
  statement {
    actions   = ["ecs:UpdateService"]
    resources = [var.service.arn]
  }

  statement {
    actions = [
      "rds:StartDBInstance",
      "rds:StopDBInstance",
    ]
    resources = [var.database.arn]
  }
}

resource "aws_iam_role_policy" "main" {
  name   = "${var.name_prefix}-office-hours"
  role   = aws_iam_role.main.id
  policy = data.aws_iam_policy_document.main.json
}

resource "aws_scheduler_schedule" "main" {
  # checkov:skip=CKV_AWS_297: entrada sem dado sensível; chave gerenciada pela AWS basta.
  for_each = local.schedule

  name                         = "${var.name_prefix}-${each.key}"
  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = each.value.target
    role_arn = aws_iam_role.main.arn
    input    = each.value.input

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}
