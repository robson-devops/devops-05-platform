data "aws_caller_identity" "current" {}

data "aws_elb_service_account" "main" {}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_s3_bucket" "access_log" {
  # checkov:skip=CKV_AWS_144: replicação não se justifica para log de laboratório.
  # checkov:skip=CKV_AWS_18: logar o acesso ao bucket de log não agrega aqui.
  # checkov:skip=CKV2_AWS_62: nada consome eventos deste bucket.
  # checkov:skip=CKV_AWS_145: o ALB só grava em bucket com SSE-S3.
  bucket        = "${var.name_prefix}-alb-log-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  rule {
    id     = "expire-access-log"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_retention_day
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.access_log]
}

data "aws_iam_policy_document" "access_log" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_log.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_log.arn,
      "${aws_s3_bucket.access_log.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_log" {
  bucket = aws_s3_bucket.access_log.id
  policy = data.aws_iam_policy_document.access_log.json

  depends_on = [aws_s3_bucket_public_access_block.access_log]
}

resource "aws_security_group" "main" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB acessivel somente pelos IPs de origem do CloudFront"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

# Prefix list gerenciada pela AWS: só a rede do CloudFront chega ao ALB.
resource "aws_vpc_security_group_ingress_rule" "cloudfront" {
  # checkov:skip=CKV_AWS_260: a origem é a prefix list do CloudFront, não 0.0.0.0/0.
  security_group_id = aws_security_group.main.id
  description       = "HTTP vindo do CloudFront"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app" {
  security_group_id = aws_security_group.main.id
  description       = "Saida para as tasks dentro da VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = var.application_port
  to_port           = var.application_port
  ip_protocol       = "tcp"
}

resource "aws_lb" "main" {
  # checkov:skip=CKV_AWS_150: deletion protection desligada para o destroy funcionar.
  # checkov:skip=CKV2_AWS_28: WAF documentado em docs/producao.md.
  # checkov:skip=CKV2_AWS_20: o HTTPS termina no CloudFront; ver docs/producao.md.
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.subnet_id
  security_groups    = [aws_security_group.main.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.access_log.id
    enabled = true
  }

  tags = {
    Name = "${var.name_prefix}-alb"
  }

  depends_on = [aws_s3_bucket_policy.access_log]
}

resource "aws_lb_target_group" "main" {
  # checkov:skip=CKV_AWS_378: HTTP do ALB até a task, dentro da VPC.
  name                 = "${var.name_prefix}-tg"
  port                 = var.application_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.name_prefix}-tg"
  }
}

resource "aws_lb_listener" "http" {
  # checkov:skip=CKV_AWS_2: só o CloudFront alcança o ALB; o HTTPS é na borda.
  # checkov:skip=CKV_AWS_103: política TLS não se aplica a listener HTTP.
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Acesso direto ao ALB nao permitido."
      status_code  = "403"
    }
  }
}

# O prefix list aceita qualquer distribuição do CloudFront; o cabeçalho prova que é a nossa.
resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = var.origin_verify_header.name
      values           = [var.origin_verify_header.value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
