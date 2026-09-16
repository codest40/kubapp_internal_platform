data "aws_route53_zone" "main" {
  provider = aws.eks
  name     = var.domain_name
}

variable "enable_route53" {
  type    = bool
  default = true
}

locals {
  subdomains = [
    "monitor",
    "app"
  ]
}

resource "aws_route53_record" "subdomains" {
  provider = aws.eks
  for_each = var.enable_route53 ? toset(local.subdomains) : []
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "${each.key}.${var.domain_name}"
  type     = "A"
  ttl      = 300
  records  = [aws_eip.sys_eip.public_ip]
}
