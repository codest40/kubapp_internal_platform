# ============================================================
# CUSTOM VPC FOR SYS_MONITOR
# ============================================================

# ------------------------------------------------------------
# Availability Zones and remote state deps
# ------------------------------------------------------------
data "aws_availability_zones" "available" {}

# ------------------------------------------------------------
# Ubuntu AMI
# ------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------
resource "aws_vpc" "sys_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ------------------------------------------------------------
# Internet Gateway
# ------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.sys_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ------------------------------------------------------------
# Public Subnet
# ------------------------------------------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.sys_vpc.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# ------------------------------------------------------------
# Route Table (Public Internet Access)
# ------------------------------------------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.sys_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------------------------------------------
# Security Group
# ------------------------------------------------------------
resource "aws_security_group" "sys_monitor" {
  name        = "${var.project_name}-sg"
  description = "Security group for Sys Monitor"
  vpc_id      = aws_vpc.sys_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Grafana"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "GitHub Exporter"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ------------------------------------------------------------
# EC2 Instance
# ------------------------------------------------------------
resource "aws_instance" "sys_monitor" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.sys_monitor.id]
  key_name                    = local.key_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.sys_monitor_local_profile.name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name = var.project_name
  }
}

# ------------------------------------------------------------
# Elastic IP
# ------------------------------------------------------------
resource "aws_eip" "sys_eip" {
  domain   = "vpc"
  instance = aws_instance.sys_monitor.id

  tags = {
    Name = "${var.project_name}-eip"
  }
}
