output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = [
    for index in var.workload_private_subnet_indices :
    aws_subnet.private[index].id
  ]
}

output "rds_proxy_private_subnet_ids" {
  description = "Private subnets selected for RDS Proxy across Availability Zones"
  value = [
    for index in var.rds_proxy_private_subnet_indices :
    aws_subnet.private[index].id
  ]
}

output "nat_public_ip" {
  value = {
    for az, eip in aws_eip.nat :
    az => eip.public_ip
  }
}

output "private_route_table_ids" {
  value = [
    for az in var.azs : aws_route_table.private[az].id
  ]
}

