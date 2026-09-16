# Run Terraform

## What It Does

The `run_tf.sh` script is a test/helper script for running Terraform
commands during development and testing.

It provides a convenient way to execute Terraform operations without
being part of the main production deployment workflow.

## What It Expects to Already Exist

The script expects:

- Terraform to be installed.
- A valid Terraform configuration to already exist.
- The script to be run from, or against, the intended Terraform working
  directory.
- Required Terraform variables and environment configuration to be
  available.
- Cloud credentials to be configured when the Terraform configuration
  interacts with AWS.
