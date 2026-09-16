# KUBAPP — Terraform Bootstrap

The `iac/boot/` directory creates the AWS resources required to store and protect KUBAPP's Terraform state.

This layer must be deployed **before** the main infrastructure under [`../infra/`](../infra/).

## Purpose

The bootstrap layer creates the resources required for Terraform's remote state backend.

| Resource       | Purpose                              |
| -------------- | ------------------------------------ |
| S3 bucket      | Stores Terraform remote state        |
| S3 versioning  | Keeps previous versions of the state |
| S3 encryption  | Protects state data at rest          |
| DynamoDB table | Provides Terraform state locking     |

This prevents the main infrastructure from depending on a local Terraform state file.

## Architecture

```text
iac/boot/
    │
    ├── S3
    │    ├── Remote Terraform State
    │    ├── Versioning
    │    └── Encryption
    │
    └── DynamoDB
         └── State Locking
              │
              ▼
        iac/infra/
              │
              ▼
       KUBAPP Infrastructure
```

## Files

| File           | Responsibility                                                                            |
| -------------- | ----------------------------------------------------------------------------------------- |
| `s3.tf`        | Creates and configures the Terraform state bucket                                         |
| `dynamodb.tf`  | Creates the state-locking table                                                           |
| `variables.tf` | Defines bootstrap configuration such as AWS region, profile, bucket, and lock table names |
| `provider.tf`  | Configures the AWS provider used to create the bootstrap resources                        |
| `version.tf`   | Defines the required Terraform version                                                    |
| `outputs.tf`   | Exposes the backend resource names and region for reference or automation                 |
| `runner.sh`    | Provides the bootstrap execution workflow                                                 |

## Deployment Order

The bootstrap layer is intentionally separate from the main infrastructure:

```text
1. iac/boot/
       │
       ▼
2. Terraform backend exists
       │
       ▼
3. iac/infra/
       │
       ▼
4. KUBAPP platform infrastructure
```

The bootstrap layer is normally created once and changed less frequently than the main infrastructure.

## Design Goal

Keep the bootstrap layer **small, stable, and independent**.
Its only responsibility is to provide the Terraform backend foundation that allows the rest of KUBAPP's infrastructure to be managed safely.


## For Users
If you intend to provision infra using this layer, then you must first create a terraform.tfvars here and supply
- profile           = "aws-accout-profile"
- state_bucket_name = "s3-bukcet-name"
- lock_table_name   = "and-lock-name"

- Then **bash runner.sh** takes over
