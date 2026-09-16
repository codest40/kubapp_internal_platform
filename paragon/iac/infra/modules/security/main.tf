
resource "aws_security_group" "sg" {
  for_each = var.sg_definitions

  name        = "${each.key}-${var.name_prefix}"
  description = each.value.description
  vpc_id      = var.vpc_id
  tags = merge(var.tags, {
    Name          = "${each.key}-${var.name_prefix}"
    resource-type = "security-group"
    cluster       = var.cluster_name
    eni-cluster   = var.cluster_name
    sg-name       = each.key
    sg-scope      = "workload"
  })
}

############################
# INGRESS (MULTI SOURCE FIX)
############################

locals {
  ingress_rules = flatten([
    for sg_name, sg in var.sg_definitions : [
      for idx, rule in sg.ingress :

      concat(
        # SG-based rules
        [
          for src in try(rule.source_sgs, []) : {
            key       = "${sg_name}-ing-${idx}-from-${src}"
            sg_name   = sg_name
            source_sg = src
            rule      = rule
          }
        ],

        # CIDR-based rule
        length(try(rule.cidr_blocks, [])) > 0 ? [
          {
            key     = "${sg_name}-ing-${idx}-cidr"
            sg_name = sg_name
            cidr    = rule.cidr_blocks
            rule    = rule
          }
        ] : []
      )
    ]
  ])
}

resource "aws_security_group_rule" "ingress" {
  for_each = {
    for r in local.ingress_rules : r.key => r
  }

  type              = "ingress"
  security_group_id = aws_security_group.sg[each.value.sg_name].id

  from_port = each.value.rule.from_port
  to_port   = each.value.rule.to_port
  protocol  = each.value.rule.protocol

  source_security_group_id = (try(each.value.source_sg, null) != null
    ? aws_security_group.sg[each.value.source_sg].id
  : null)

  cidr_blocks = try(each.value.cidr, null)

  description = try(each.value.rule.description, null)
}

############################
# EGRESS
############################

locals {
  egress_rules = flatten([
    for sg_name, sg in var.sg_definitions : [
      for idx, rule in sg.egress :

      concat(
        # SG-based expansion
        [
          for target in try(rule.source_sgs, []) : {
            key       = "${sg_name}-eg-${idx}-to-${target}"
            sg_name   = sg_name
            target_sg = target
            rule      = rule
          }
        ],

        # CIDR-based
        length(try(rule.cidr_blocks, [])) > 0 ? [
          {
            key     = "${sg_name}-eg-${idx}-cidr"
            sg_name = sg_name
            cidr    = rule.cidr_blocks
            rule    = rule
          }
        ] : []
      )
    ]
  ])
}

resource "aws_security_group_rule" "egress" {
  for_each = {
    for r in local.egress_rules : r.key => r
  }

  type              = "egress"
  security_group_id = aws_security_group.sg[each.value.sg_name].id

  from_port = each.value.rule.from_port
  to_port   = each.value.rule.to_port
  protocol  = each.value.rule.protocol

  # SG-based
  source_security_group_id = (try(each.value.target_sg, null) != null
    ? aws_security_group.sg[each.value.target_sg].id
  : null)

  # CIDR-based
  cidr_blocks = try(each.value.cidr, null)

  description = try(each.value.rule.description, null)
}
