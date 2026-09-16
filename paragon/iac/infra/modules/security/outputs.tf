############################
# Outputs
############################

output "sg_ids" {
  description = "Map of security group IDs by role"
  value = {
    for k, sg in aws_security_group.sg :
    k => sg.id
  }
}

