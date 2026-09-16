# DNS Infrastructure

Dedicated Terraform stack for managing KUBAPP Route53 hosted zones.

This stack is intentionally separate from the main KUBAPP infrastructure.

## Structure

```text
iac/dns/
├── backend.hcl
├── bootstrap.sh
├── runner.sh
├── providers.tf
├── variables.tf
├── backend.tf
├── route53.tf
├── outputs.tf
├── versions.tf
└── terraform.tfvars
```

## What It Manages

* Route53 hosted zones
* Multiple domains through `for_each`
* Dedicated S3 Terraform state
* Terraform state locking through the S3 backend lockfile

The stack does not manage EKS, VPC, IAM, applications, or other KUBAPP infrastructure.

## Backend

The DNS state uses a dedicated S3 bucket:

```text
kubapp-dns-tf-state-<AWS_ACCOUNT_ID>
```

`backend.hcl`:

```hcl
bucket       = "xxx"
key          = "xxx"
region       = "us-east-1"
use_lockfile = true
encrypt      = true
```

The backend bucket is created separately by `bootstrap.sh`.

## Usage

Set the AWS profile:

```bash
export AWS_PROFILE=<profile>
```

Create the backend:

```bash
./runner.sh create <profile>
```

Initialize and apply:

```bash
./runner.sh apply
```

Destroy managed DNS resources:

```bash
./runner.sh destroy
```

Delete the Terraform state bucket only when the DNS infrastructure is no longer required:

```bash
./bootstrap.sh delete
```

`bootstrap.sh delete` requires explicit confirmation and removes all object
versions and delete markers before deleting the bucket.

## Configuration

`terraform.tfvars` supplies the AWS profile, region, and domains.


## Outputs

Terraform exposes:

* hosted zone IDs
* nameservers
* domain/zone information

These outputs are consumed by other infrastructure (infra, boot, k8s) or DNS configuration
without coupling those stacks to this Terraform state.
