
terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.30.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "2.12.0"
    }
  }
}

