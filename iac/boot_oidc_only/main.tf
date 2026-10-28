
terraform {
  required_version = "~> 1.14"
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

terraform {
  backend "local" {}
}

