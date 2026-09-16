# EKS

The `eks/` module provisions the Amazon EKS cluster and its Kubernetes compute and access configuration.

## Purpose

KUBAPP uses Amazon EKS as its managed Kubernetes control plane. This module brings together the cluster, worker capacity, Fargate workloads, Kubernetes access, and OIDC identity required to run the platform.

## What It Creates

| Resource                        | Purpose                                        |
| ------------------------------- | ---------------------------------------------- |
| EKS cluster                     | Provides the managed Kubernetes control plane  |
| EC2 application node group      | Runs application workloads on EC2              |
| EC2 system node group           | Runs platform and system workloads             |
| Fargate profiles                | Runs selected workloads without managing nodes |
| Fargate security group          | Controls network access for Fargate workloads  |
| EKS access entries and policies | Controls access to the Kubernetes cluster      |
| EKS OIDC provider               | Enables IAM Roles for Service Accounts (IRSA)  |

Example:

```text
                         KUBAPP
                            │
                            ▼
                       EKS Cluster
                            │
             ┌──────────────┼──────────────┐
             ▼              ▼              ▼
        System Nodes   Application Nodes  Fargate
             │              │              │
             └──────────────┴──────────────┘
                            │
                     Kubernetes Workloads
```

## Why KUBAPP Uses It

EKS provides KUBAPP with a managed Kubernetes control plane while allowing the platform to choose how different workloads are executed.

This provides:

* Managed Kubernetes control plane
* Dedicated capacity for system workloads
* EC2 capacity for application workloads
* Serverless execution through Fargate
* Controlled Kubernetes access
* OIDC-based workload identity for AWS access

Separating system and application capacity also helps prevent platform components from competing directly with application workloads for compute resources.

## Module Inputs

| Input                       | Purpose                                      |
| --------------------------- | -------------------------------------------- |
| `cluster_name`              | Name of the EKS cluster                      |
| `vpc_id`                    | VPC where the cluster is deployed            |
| `private_subnet_ids`        | Private subnets used by EKS                  |
| `cluster_role_arn`          | IAM role used by the EKS control plane       |
| `node_group_role_arn`       | IAM role used by EC2 worker nodes            |
| `fargate_role_arn`          | IAM role used by Fargate profiles            |
| `fargate_security_group_id` | Security group assigned to Fargate workloads |
| `oidc_provider_arn`         | OIDC provider used for workload identity     |
| `tags`                      | Common resource tags                         |

## Outputs

| Output                               | Purpose                                          |
| ------------------------------------ | ------------------------------------------------ |
| `cluster_id`                         | EKS cluster identifier                           |
| `cluster_arn`                        | ARN of the EKS cluster                           |
| `cluster_endpoint`                   | Kubernetes API server endpoint                   |
| `cluster_certificate_authority_data` | Certificate authority data for Kubernetes access |
| `oidc_provider_arn`                  | EKS OIDC provider ARN used by IRSA               |

## KUBAPP Role

This module provides the **Kubernetes compute and control plane layer** of KUBAPP.
It establishes the EKS environment where platform services and application workloads run, while integrating AWS IAM, networking, and workload identity into the cluster.
