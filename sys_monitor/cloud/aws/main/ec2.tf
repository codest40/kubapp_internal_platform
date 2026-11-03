data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_instance_profile" "sys_monitor" {
  name = "sys-monitor-ec2-profile"
}

resource "aws_instance" "sys_monitor" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.sys_monitor.id
  vpc_security_group_ids      = [aws_security_group.sys_monitor.id]
  iam_instance_profile        = data.aws_iam_instance_profile.sys_monitor.name
  associate_public_ip_address = true
  key_name                    = aws_key_pair.sys_monitor.key_name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    cluster_mode      = var.cluster_mode
    account_id        = var.account_id
    kubapp_account_id = var.kubapp_account_id
    region            = var.region
    domain            = local.domain_name
  })
  tags = {
    Name = "sys-monitor"
  }
  depends_on = [
    aws_ssm_parameter.backend_env,
    aws_ssm_parameter.github_deploy_key,
    aws_route53_record.monitor,
    aws_route53_record.grafana,
    aws_route53_record.prometheus,
    aws_route53_record.github,
    aws_route53_record.codebase,
    aws_route53_record.gitops,
  ]
}

resource "aws_eip" "sys_monitor" {
  domain = "vpc"

  tags = {
    Name = "sys-monitor"
  }
}

resource "aws_eip_association" "sys_monitor" {
  instance_id   = aws_instance.sys_monitor.id
  allocation_id = aws_eip.sys_monitor.id
}

resource "aws_key_pair" "sys_monitor" {
  key_name   = "sys-monitor"
  public_key = file(pathexpand("~/.ssh/sys-monitor.pub"))
}


