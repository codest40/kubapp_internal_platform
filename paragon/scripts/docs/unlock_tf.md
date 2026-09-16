# Unlock Terraform

## What It Does

The `unlock_tf.sh` script removes a Terraform state lock when Terraform
has left the state locked and normal operations cannot continue.

It is intended as a recovery utility for situations such as an interrupted
Terraform operation or stale state lock.

## What It Expects to Already Exist

The script expects:

- Terraform to be installed.
- The Terraform working directory and configuration to already exist.
- The Terraform backend to already be configured.
- Access to the remote Terraform state.
- The required AWS credentials and permissions when using the AWS backend.
- The Terraform lock ID or other required input expected by the script.
