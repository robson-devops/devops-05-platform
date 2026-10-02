# Repositório da camada shared: a mesma imagem passa por dev e prod.
data "aws_ecr_repository" "app" {
  name = "${var.project_name}-app"
}

module "platform" {
  source = "../../modules/platform"

  project_name      = var.project_name
  environment       = "dev"
  vpc_cidr          = "10.50.0.0/16"
  availability_zone = ["${var.aws_region}a", "${var.aws_region}b"]

  # Dev: um NAT, banco single-AZ, uma task e desligado fora do horário.
  single_nat_gateway  = true
  enable_office_hours = true
  enable_backup       = false

  image = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"

  service = {
    desired_count = 1
    cpu           = 256
    memory        = 512
  }

  database = {
    instance_class = "db.t4g.micro"
    multi_az       = false
  }

  monthly_budget_usd = var.monthly_budget_usd
  alert_email        = var.alert_email
}
