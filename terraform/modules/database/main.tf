resource "aws_db_subnet_group" "main" {
  name       = local.identifier
  subnet_ids = var.subnet_id

  tags = {
    Name = local.identifier
  }
}

# Sem regra de entrada aqui: quem chama o módulo libera a origem.
resource "aws_security_group" "main" {
  name        = "${local.identifier}-sg"
  description = "PostgreSQL acessivel somente pelos security groups autorizados"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.identifier}-sg"
  }
}

resource "aws_db_parameter_group" "main" {
  name   = "${local.identifier}-postgres${var.engine_version}"
  family = "postgres${var.engine_version}"

  # Parâmetro estático: a AWS só aceita aplicar no próximo reboot.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # Só DDL: registrar toda consulta gravaria também os dados.
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Criado antes da instância; senão o RDS cria sem retenção e ele sobra no destroy.
resource "aws_cloudwatch_log_group" "database" {
  # checkov:skip=CKV_AWS_158: chave gerenciada pela AWS basta aqui.
  # checkov:skip=CKV_AWS_338: retenção curta em ambiente de laboratório.
  for_each = toset(local.log_export)

  name              = "/aws/rds/instance/${local.identifier}/${each.key}"
  retention_in_days = var.log_retention_day
}

resource "aws_db_instance" "main" {
  # checkov:skip=CKV_AWS_157: multi_az é variável; o dev usa single-AZ por custo.
  # checkov:skip=CKV_AWS_293: deletion_protection é variável; desligado no laboratório.
  # checkov:skip=CKV_AWS_118: enhanced monitoring não se justifica nesta escala.
  # checkov:skip=CKV_AWS_354: Performance Insights com a chave gerenciada pela AWS.
  # checkov:skip=CKV2_AWS_30: log de consultas ligado só para DDL e consultas lentas.
  # checkov:skip=CKV_AWS_226: logs exportados com a chave gerenciada pela AWS.
  identifier     = local.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.database_name
  username = var.master_username

  # Senha no Secrets Manager, gerada e rotacionada pela AWS; nunca no state.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.allocated_storage_gb * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = [aws_security_group.main.id]
  multi_az               = var.multi_az
  publicly_accessible    = false

  backup_retention_period    = var.backup_retention_day
  delete_automated_backups   = true
  copy_tags_to_snapshot      = true
  skip_final_snapshot        = true
  deletion_protection        = var.deletion_protection
  auto_minor_version_upgrade = true
  apply_immediately          = true

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = local.log_export

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Name = local.identifier
  }

  depends_on = [aws_cloudwatch_log_group.database]
}
