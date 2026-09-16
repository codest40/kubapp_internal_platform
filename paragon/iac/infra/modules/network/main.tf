############################################
# VPC
############################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      resource-type = "vpc"
      network-scope = "core"
      eni-cluster   = var.cluster_name
      eni-domain    = "network"
      Name          = "${var.name}-vpc"
    }
  )
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    resource-type = "iam-role"
    layer         = "identity"
    iam-purpose   = "vpc-flow-logs"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.name}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = var.vpc_flow_log_arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
  tags = merge(var.tags, {
    resource-type = "vpc-flow-log"
    layer         = "observability"
    log-type      = "vpc-flow"
  })
}


############################################
# Internet Gateway
############################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = merge(var.tags, {
    Name          = "${var.name}-igw"
    resource-type = "internet-gateway"
    network-role  = "egress"
  })
}

############################################
# Public Subnets
############################################
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name          = "${var.name}-public-${count.index}"
    resource-type = "subnet"
    subnet-type   = "public"
    az            = var.azs[count.index]
    routing       = "internet-facing"

    # EKS REQUIRED
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/elb"            = "1"
  })
}

############################################
# Private Subnets
############################################
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, {
    Name                                = "${var.name}-private-${count.index}"
    resource-type                       = "subnet"
    subnet-type                         = "private"
    az                                  = var.azs[count.index]
    routing                             = "nat"
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/internal-elb"   = "1"
  })
}

############################################
# Elastic IP for NAT
############################################
resource "aws_eip" "nat" {
  for_each = toset(var.azs)

  domain = "vpc"

  tags = merge(var.tags, {
    Name          = "${var.name}-nat-eip-${each.key}"
    resource-type = "eip"
    az            = each.key
  })
}

############################################
# NAT Gateway (Multl NAT - per design)
############################################
resource "aws_nat_gateway" "nat" {
  for_each = toset(var.azs)

  allocation_id = aws_eip.nat[each.key].id

  subnet_id = aws_subnet.public[
    index(var.azs, each.key)
  ].id

  tags = merge(var.tags, {
    Name          = "${var.name}-nat-${each.key}"
    resource-type = "nat-gateway"
    az            = each.key
  })

  depends_on = [aws_internet_gateway.igw]
}

############################################
# Public Route Table
############################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(var.tags, {
    Name          = "${var.name}-public-rt"
    resource-type = "route-table"
    subnet-type   = "public"
  })
}

############################################
# Public Route Table Association
############################################
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

############################################
# Private Route Table
############################################
resource "aws_route_table" "private" {
  for_each = toset(var.azs)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[each.key].id
  }

  tags = merge(var.tags, {
    Name          = "${var.name}-private-rt-${each.key}"
    resource-type = "route-table"
    az            = each.key
  })
}

############################################
# Private Route Table Association
############################################
resource "aws_route_table_association" "private" {
  count     = length(var.private_subnets)
  subnet_id = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[
    var.azs[count.index]
  ].id
}

