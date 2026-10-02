locals {
  az_index = { for index, az in var.availability_zone : az => index }

  # Terceiro octeto: 0+ pública, 10+ aplicação, 20+ dados.
  public_subnet = { for az, index in local.az_index : az => cidrsubnet(var.vpc_cidr, 8, index) }
  app_subnet    = { for az, index in local.az_index : az => cidrsubnet(var.vpc_cidr, 8, 10 + index) }
  data_subnet   = { for az, index in local.az_index : az => cidrsubnet(var.vpc_cidr, 8, 20 + index) }

  nat_az = var.single_nat_gateway ? [var.availability_zone[0]] : var.availability_zone
}
