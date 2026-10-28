output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
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

