resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnet

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name = "${var.name_prefix}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "app" {
  for_each = local.app_subnet

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name = "${var.name_prefix}-app-${each.key}"
    Tier = "app"
  }
}

resource "aws_subnet" "data" {
  for_each = local.data_subnet

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name = "${var.name_prefix}-data-${each.key}"
    Tier = "data"
  }
}

resource "aws_eip" "nat" {
  # checkov:skip=CKV2_AWS_19: o EIP fica no NAT Gateway, não numa instância.
  for_each = toset(local.nat_az)

  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  for_each = toset(local.nat_az)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = {
    Name = "${var.name_prefix}-nat-${each.key}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Uma tabela por AZ: com NAT por AZ, a saída não cruza de zona.
resource "aws_route_table" "app" {
  for_each = local.app_subnet

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? local.nat_az[0] : each.key].id
  }

  tags = {
    Name = "${var.name_prefix}-app-${each.key}"
  }
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# Sem rota padrão: o banco não tem caminho para a internet.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-data"
  }
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data.id
}

# Esvazia o SG default para que nada caia nele por engano.
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-default-bloqueado"
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  # checkov:skip=CKV_AWS_158: chave gerenciada pela AWS basta aqui.
  # checkov:skip=CKV_AWS_338: retenção curta em ambiente de laboratório.
  name              = "/${var.name_prefix}/vpc-flow-log"
  retention_in_days = var.flow_log_retention_day
}

data "aws_iam_policy_document" "flow_log_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_log" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_log.arn}:*"]
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "${var.name_prefix}-flow-log"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume_role.json
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "${var.name_prefix}-flow-log"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow_log.json
}

resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.flow_log.arn
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn

  tags = {
    Name = "${var.name_prefix}-flow-log"
  }
}
