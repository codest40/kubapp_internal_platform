resource "aws_route53_zone" "domain" {
  for_each = var.domains

  name = each.key

  tags = {
    project    = "kubapp"
    component  = "dns"
    domain     = each.key
    managed-by = "terraform"
  }
}
