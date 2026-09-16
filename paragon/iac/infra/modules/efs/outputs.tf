output "efs_id" {
  value = aws_efs_file_system.this.id
}

output "efs_dns_name" {
  value = aws_efs_file_system.this.dns_name
}

output "efs_security_group_id" {
  value = aws_security_group.efs.id
}

#output "efs_access_points" {
#  value = {
#    for k, v in aws_efs_access_point.this : k => {
#      id  = v.id
#      arn = v.arn
#    }
#  }
#}
