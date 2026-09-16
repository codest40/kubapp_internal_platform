# Pre Checks

## What It Does

The `prechecks.sh` script performs prerequisite checks before starting a
Kubapp deployment or infrastructure operation.

It verifies that the required environment, tools, configuration, and
access are available before the main workflow proceeds.

## What It Expects to Already Exist

The script expects:

- The required command-line tools to be installed.
- AWS credentials and permissions to be configured when AWS operations
  are required.
- `kubectl` to be configured when Kubernetes checks are required.
- The required Terraform and GitOps configuration to already exist.
- The target environment and required environment variables to be
  available.
- Access to the infrastructure and repositories required by the
  deployment workflow.
