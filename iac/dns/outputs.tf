output "domains" {
  description = "Route53 hosted zone information keyed by domain."

  value = {
    for domain, zone in aws_route53_zone.domain :
    domain => {
      domain       = zone.name
      zone_id      = zone.zone_id
      name_servers = zone.name_servers
    }
  }
}

output "zone_ids" {
  description = "Route53 hosted zone IDs keyed by domain."

  value = {
    for domain, zone in aws_route53_zone.domain :
    domain => zone.zone_id
  }
}

output "name_servers" {
  description = "Route53 nameservers keyed by domain."

  value = {
    for domain, zone in aws_route53_zone.domain :
    domain => zone.name_servers
  }
}
