# EFS

The `efs/` module provisions Amazon Elastic File System (EFS) for shared persistent storage within KUBAPP.

## Purpose

Some applications need persistent storage that can be accessed by multiple workloads or pods. This module provides a shared, managed filesystem that can be mounted from resources inside the KUBAPP VPC.

## What It Creates

| Resource           | Purpose                                              |
| ------------------ | ---------------------------------------------------- |
| EFS filesystem     | Provides shared persistent storage                   |
| EFS mount targets  | Makes the filesystem accessible from private subnets |
| Security group     | Controls NFS access to EFS                           |
| Encryption at rest | Protects stored data                                 |

Example:

```text id="r5r9l5"
KUBAPP Private Subnets
        │
        ├── EFS Mount Target
        │
        ├── EFS Mount Target
        │
        └── EFS Mount Target
                │
                ▼
        Shared EFS Filesystem
                ▲
                │
        Kubernetes Workloads
```

## Why KUBAPP Uses It

EFS provides shared persistent storage without requiring KUBAPP to manage storage servers.

It is useful for workloads that require:

* Persistent data
* Shared filesystem access
* Storage across multiple availability zones
* Kubernetes workloads that need network-based storage

## Security

The EFS security group restricts NFS access to the KUBAPP VPC, while the filesystem is encrypted at rest.

## Module Inputs

| Input          | Purpose                                   |
| -------------- | ----------------------------------------- |
| `vpc_id`       | VPC where EFS is deployed                 |
| `vpc_cidr`     | Network range allowed to access EFS       |
| `subnet_ids`   | Private subnets for EFS mount targets     |
| `name_prefix`  | Consistent resource naming                |
| `cluster_name` | Associates EFS resources with the cluster |
| `tags`         | Common resource tags                      |

## Outputs

| Output                  | Purpose                                |
| ----------------------- | -------------------------------------- |
| `efs_id`                | EFS filesystem ID                      |
| `efs_dns_name`          | DNS name used to access the filesystem |
| `efs_security_group_id` | Security group protecting EFS          |

## KUBAPP Role

This module provides the **shared persistent storage layer** for applications that require filesystem persistence beyond the lifecycle of individual Kubernetes pods.
