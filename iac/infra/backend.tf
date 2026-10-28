terraform {
  backend "s3" {
    bucket       = "kubapp-tf-state-704048935807"
    key          = "dev/infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
