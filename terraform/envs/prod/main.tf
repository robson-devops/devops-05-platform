# Repositório da camada shared: a mesma imagem passa por dev e prod.
data "aws_ecr_repository" "app" {
  name = "${var.project_name}-app"
}

module "platform" {
  source = "../../modules/platform"

  project_name      = var.project_name
  environment       = "prod"
  vpc_cidr          = "10.60.0.0/16"
  availability_zone = ["${var.aws_region}a", "${var.aws_region}b"]

  # Prod: um NAT por AZ, banco Multi-AZ, duas tasks e backup diário.
  single_nat_gateway  = false
  enable_office_hours = false
  enable_backup       = true

  image = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"

  service = {
    desired_count = 2
    cpu           = 256
    memory        = 512
  }

  database = {
    instance_class = "db.t3.micro"
    multi_az       = true
  }

  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.alert_email
}
