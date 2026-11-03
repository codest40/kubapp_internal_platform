terraform {
  backend "s3" {
    bucket       = "kubapp-tf-state-704048935807"
    key          = "dev/manifests/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
