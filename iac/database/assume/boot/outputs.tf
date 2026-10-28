output "bucket_name" {
  value = aws_s3_object.terraform_state.bucket
}

output "state_key" {
  value = aws_s3_object.terraform_state.key
}
