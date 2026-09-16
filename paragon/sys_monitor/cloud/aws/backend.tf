
terraform {
  backend "s3" {
    bucket  = "kubapp-sys-monitor"
    key     = "dev/tf-state"
    region  = "us-east-1"
    encrypt = true
  }
}
