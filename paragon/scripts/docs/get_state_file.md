# Get State File

## What It Does

The `get_state_file.sh` script retrieves the Terraform state file used by
the Kubapp infrastructure.

It is used to access the remote Terraform state when inspecting or
working with the infrastructure state outside the normal Terraform
workflow.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed and configured.
- Access to the Terraform state backend.
- The Terraform S3 backend and state bucket to already exist.
- The required AWS credentials and permissions.
- The expected Terraform state path/key to already be configured or
  provided to the script.
- The target AWS region to be available.
