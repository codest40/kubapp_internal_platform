# KubApp — Infrastructure as Code (IaC Layer — Terraform)

## OVERVIEW
#### This directory defines the complete AWS + Kubernetes infrastructure foundation for Kubapp using Terraform modules, multi-environment state management, and layered separation of concerns.

## The system is structured into four major domains:
```
 iac/
 ├── infra/        # AWS + EKS infrastructure modules
 ├── k8s/          # Kubernetes platform configuration layer
 ├── manifests/    # Kubernetes resources via Terraform
 ├── boot/         # Terraform backend bootstrap
 ├── README.md
```

## ARCHITECTURE

 This IaC layer follows a 3-tier infrastructure model:

 1. FOUNDATION LAYER (boot)
 2. INFRASTRUCTURE LAYER (infra)
 3. PLATFORM LAYER (k8s + manifests)


