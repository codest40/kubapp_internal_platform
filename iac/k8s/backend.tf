terraform {
  backend "s3" {
    bucket       = "kubapp-tf-state-704048935807"
    key          = "dev/k8s/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
