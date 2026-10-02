data "aws_region" "current" {}

# Nome exato que o ECS usaria; criado aqui para ter retenção e sair no destroy.
resource "aws_cloudwatch_log_group" "container_insight" {
  # checkov:skip=CKV_AWS_158: chave gerenciada pela AWS basta aqui.
  # checkov:skip=CKV_AWS_338: retenção curta em ambiente de laboratório.
  name              = "/aws/ecs/containerinsights/${var.name_prefix}/performance"
  retention_in_days = var.log_retention_day
}

resource "aws_ecs_cluster" "main" {
  name = var.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  depends_on = [aws_cloudwatch_log_group.container_insight]
}

resource "aws_cloudwatch_log_group" "app" {
  # checkov:skip=CKV_AWS_158: chave gerenciada pela AWS basta aqui.
  # checkov:skip=CKV_AWS_338: retenção curta em ambiente de laboratório.
  name              = "/${var.name_prefix}/app"
  retention_in_days = var.log_retention_day
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: usada pelo agente do ECS para puxar a imagem, gravar log e ler o secret.
resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-execution"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_database_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.database.secret_arn]
  }
}

resource "aws_iam_role_policy" "read_database_secret" {
  name   = "${var.name_prefix}-read-database-secret"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_database_secret.json
}

# Task role: usada pelo container. A aplicação não chama a AWS; só o ECS Exec.
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "execute_command" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "execute_command" {
  name   = "${var.name_prefix}-execute-command"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.execute_command.json
}

resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task-sg"
  description = "Tasks da aplicacao: entrada somente pelo ALB"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-task-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.task.id
  description                  = "Trafego da aplicacao vindo do ALB"
  referenced_security_group_id = var.alb_security_group_id
  from_port                    = var.application_port
  to_port                      = var.application_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  # checkov:skip=CKV_AWS_382: saída pelo NAT para ECR, CloudWatch e Secrets Manager.
  security_group_id = aws_security_group.task.id
  description       = "Saida para o banco e para as APIs da AWS via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_ecs_task_definition" "main" {
  family                   = var.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.image
      essential = true

      portMappings = [
        {
          containerPort = var.application_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_ENV", value = var.environment },
        { name = "DB_HOST", value = var.database.endpoint },
        { name = "DB_PORT", value = tostring(var.database.port) },
        { name = "DB_NAME", value = var.database.name },
        { name = "DB_USER", value = var.database.username },
        { name = "DB_SSLMODE", value = "require" },
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.database.secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "app"
        }
      }

      readonlyRootFilesystem = true

      mountPoints = [
        {
          sourceVolume  = "tmp"
          containerPath = "/tmp"
          readOnly      = false
        }
      ]
    }
  ])

  volume {
    name = "tmp"
  }
}

resource "aws_ecs_service" "main" {
  name            = var.name_prefix
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = true

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  availability_zone_rebalancing      = "ENABLED"
  health_check_grace_period_seconds  = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = var.application_port
  }

  # A imagem é do pipeline e a quantidade, do agendamento de horário.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
