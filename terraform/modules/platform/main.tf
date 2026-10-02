resource "random_password" "origin_verify" {
  length  = 40
  special = false
}

module "network" {
  source = "../network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zone  = var.availability_zone
  single_nat_gateway = var.single_nat_gateway
}

module "database" {
  source = "../database"

  name_prefix    = local.name_prefix
  vpc_id         = module.network.vpc_id
  subnet_id      = module.network.data_subnet_id
  instance_class = var.database.instance_class
  multi_az       = var.database.multi_az
}

module "load_balancer" {
  source = "../load_balancer"

  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  vpc_cidr             = module.network.vpc_cidr
  subnet_id            = module.network.public_subnet_id
  origin_verify_header = local.origin_verify_header
}

module "cdn" {
  source = "../cdn"

  name_prefix          = local.name_prefix
  origin_domain_name   = module.load_balancer.dns_name
  origin_verify_header = local.origin_verify_header
}

module "ecs_service" {
  source = "../ecs_service"

  name_prefix           = local.name_prefix
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.app_subnet_id
  alb_security_group_id = module.load_balancer.security_group_id
  target_group_arn      = module.load_balancer.target_group_arn
  image                 = var.image
  desired_count         = var.service.desired_count
  cpu                   = var.service.cpu
  memory                = var.service.memory

  database = {
    endpoint   = module.database.endpoint
    port       = module.database.port
    name       = module.database.database_name
    username   = module.database.master_username
    secret_arn = module.database.master_user_secret_arn
  }
}

# Única origem aceita pelo banco: as tasks da aplicação.
resource "aws_vpc_security_group_ingress_rule" "database_from_app" {
  security_group_id            = module.database.security_group_id
  description                  = "PostgreSQL a partir das tasks"
  referenced_security_group_id = module.ecs_service.security_group_id
  from_port                    = module.database.port
  to_port                      = module.database.port
  ip_protocol                  = "tcp"
}

module "backup" {
  source = "../backup"
  count  = var.enable_backup ? 1 : 0

  name_prefix  = local.name_prefix
  resource_arn = { database = module.database.arn }
}

module "office_hours" {
  source = "../office_hours"
  count  = var.enable_office_hours ? 1 : 0

  name_prefix   = local.name_prefix
  desired_count = var.service.desired_count

  service = {
    cluster_name = module.ecs_service.cluster_name
    name         = module.ecs_service.service_name
    arn          = module.ecs_service.service_arn
  }

  database = {
    identifier = module.database.identifier
    arn        = module.database.arn
  }
}

module "budget" {
  source = "../budget"

  name_prefix       = local.name_prefix
  environment       = var.environment
  monthly_limit_usd = var.monthly_budget_usd
  alert_email       = var.alert_email
}
