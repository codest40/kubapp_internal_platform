resource "aws_acm_certificate" "kubapp" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]

  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.kubapp.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "kubapp" {
  certificate_arn         = aws_acm_certificate.kubapp.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

output "acm_cert_arn" {
  value = aws_acm_certificate_validation.kubapp.certificate_arn
}
