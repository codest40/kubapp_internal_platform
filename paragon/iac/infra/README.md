# KUBAPP — Infrastructure

The `infra/` directory contains the **AWS infrastructure foundation** for KUBAPP, managed entirely with Terraform.

Its purpose is to provision the cloud environment required to run and operate KUBAPP's Kubernetes platform in a consistent, repeatable, and secure way.

## Purpose

The infrastructure layer provides the foundation on which the rest of KUBAPP runs.

It is responsible for:

* AWS networking
* Network security
* AWS and Kubernetes identity
* EKS compute
* Persistent storage
* TLS and DNS integration
* Centralized logging

The infrastructure is designed to keep these responsibilities separated into reusable Terraform modules.

## Architecture

At a high level, the infrastructure follows this structure:

```text
                    AWS
                     │
                     ▼
                  Network
                     │
             ┌───────┴───────┐
             ▼               ▼
          Security          IAM
             │               │
             └───────┬───────┘
                     ▼
                    EKS
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
        EC2       Fargate     Storage
                                 │
                                 ▼
                                EFS

       Logging ─────────────► Observability
       ACM / DNS ───────────► HTTPS / Edge
```

Each area is implemented as an independent Terraform module and connected through the root infrastructure configuration.

## Design Goals

### Modular

Infrastructure responsibilities are separated into focused Terraform modules.

This makes the platform easier to understand, maintain, and extend.

### Secure

Workloads run within controlled network boundaries, while AWS permissions are separated by role and workload identity.

### Reproducible

The entire infrastructure is defined as code, allowing environments to be provisioned consistently rather than manually configured.

### Environment-Aware

KUBAPP supports different deployment environments such as `dev`, `staging`, and `prod` through Terraform configuration and environment-specific state.

### Production-Oriented

The infrastructure provides the fundamental capabilities required to operate Kubernetes workloads reliably on AWS, including networking, identity, storage, logging, and HTTPS.

## Infrastructure Modules

The major infrastructure responsibilities are separated into modules:

```text
modules/
├── acm/          # TLS certificates
├── efs/          # Shared persistent storage
├── eks/          # Kubernetes platform
├── iam-core/     # Core AWS identities
├── iam-irsa/     # Kubernetes workload identities
├── logging/      # Centralized CloudWatch logging
├── network/      # VPC and networking
├── security/     # AWS security groups
└── sg-prep/      # Security group definitions
```

Each module contains its own README explaining its specific responsibility and its role within KUBAPP.

## Root Terraform Files

The root Terraform files provide the **control layer** for the infrastructure.

| File           | Responsibility                                                                                                   |
| -------------- | ---------------------------------------------------------------------------------------------------------------- |
| `main.tf`      | Composes the infrastructure modules and connects their inputs and outputs                                        |
| `variables.tf` | Defines the inputs required by the infrastructure                                                                |
| `local.tf`     | Defines reusable and derived values such as naming, tagging, logging configuration, and environment-aware values |
| `providers.tf` | Configures the Terraform providers used to manage AWS and other infrastructure APIs                              |
| `versions.tf`  | Defines Terraform and provider version requirements for reproducible deployments                                 |
| `backend.tf`   | Configures remote Terraform state and state locking using S3                                                     |
| `outputs.tf`   | Exposes important infrastructure values for other layers and automation                                          |

## Environments

The `envs/` directory contains environment-specific configuration.

This allows the same infrastructure design to be used for environments such as:

```text
envs/
├── dev/
└── prod/
```

Environment configuration supplies values such as:

* Environment name
* Cluster configuration
* Domain configuration
* Infrastructure sizing
* Logging settings

The infrastructure code remains shared while environment-specific values are kept separate.

## Role in KUBAPP

The `infra/` layer is the **cloud foundation of KUBAPP**.

It does not deploy application workloads itself. Instead, it provides the AWS and Kubernetes infrastructure required by the higher layers of the platform.

