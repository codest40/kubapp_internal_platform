output "bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "state_key" {
  value = local.state_key
}
