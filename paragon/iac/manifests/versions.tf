terraform {
  required_version = "~> 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.30.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "5.60.0"
    }
  }
}
