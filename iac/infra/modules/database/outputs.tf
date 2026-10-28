
output "kubapp_reads_db_state" {
  value = aws_iam_role.kubapp_db_state_reader.arn
}

