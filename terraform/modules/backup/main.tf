resource "aws_backup_vault" "main" {
  # checkov:skip=CKV_AWS_166: chave gerenciada pela AWS; uma chave própria sobraria 7 dias após o destroy.
  name = "${var.name_prefix}-backup"

  # Apaga os pontos de recuperação junto com o cofre no destroy.
  force_destroy = true
}

resource "aws_backup_plan" "main" {
  name = "${var.name_prefix}-diario"

  rule {
    rule_name         = "diario"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.schedule_expression
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.retention_day
    }
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

# A mesma role faz o backup e o teste de restauração.
resource "aws_iam_role" "main" {
  name               = "${var.name_prefix}-backup"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "main" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.main.name
  policy_arn = each.value
}

resource "aws_backup_selection" "main" {
  name         = "${var.name_prefix}-recursos"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.main.arn
  resources    = values(var.resource_arn)
}
