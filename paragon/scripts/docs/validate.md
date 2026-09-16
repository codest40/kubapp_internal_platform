# Validate

## What It Does

The `validate.sh` script performs validation checks for a Kubapp
environment before deployment or activation.

It verifies that the required configuration and infrastructure inputs are
valid before the main workflow continues.

## What It Expects to Already Exist

The script expects:

- The target environment configuration to already exist.
- The required Terraform and Kubapp configuration files to be available.
- The command-line tools used by the validation checks to be installed.
- Required AWS credentials and permissions when AWS validation is
  performed.
- Any required environment variables or configuration values to be
  available.

The environment is provided as the first argument.

```bash
./scripts/validate.sh dev
