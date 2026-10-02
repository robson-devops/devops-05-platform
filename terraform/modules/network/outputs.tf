output "app_subnet_id" {
  description = "Subnets privadas da aplicação, com saída pelo NAT"
  value       = [for subnet in aws_subnet.app : subnet.id]
}

output "data_subnet_id" {
  description = "Subnets privadas de dados, sem rota para a internet"
  value       = [for subnet in aws_subnet.data : subnet.id]
}

output "nat_public_ip" {
  description = "IPs públicos de saída da aplicação"
  value       = [for eip in aws_eip.nat : eip.public_ip]
}

output "public_subnet_id" {
  description = "Subnets públicas, onde fica o ALB"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "vpc_cidr" {
  description = "CIDR da VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.main.id
}
