resource "aws_vpc" "sys_monitor" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "sys-monitor-vpc"
  }
}

resource "aws_internet_gateway" "sys_monitor" {
  vpc_id = aws_vpc.sys_monitor.id

  tags = {
    Name = "sys-monitor-igw"
  }
}

resource "aws_subnet" "sys_monitor" {
  vpc_id                  = aws_vpc.sys_monitor.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "sys-monitor-subnet"
  }
}

resource "aws_route_table" "sys_monitor" {
  vpc_id = aws_vpc.sys_monitor.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sys_monitor.id
  }

  tags = {
    Name = "sys-monitor-route-table"
  }
}

resource "aws_route_table_association" "sys_monitor" {
  subnet_id      = aws_subnet.sys_monitor.id
  route_table_id = aws_route_table.sys_monitor.id
}
