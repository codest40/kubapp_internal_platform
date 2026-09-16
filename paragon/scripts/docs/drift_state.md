# Drift State

## What It Does

The `drift_state.sh` script checks the current infrastructure state for
resource drift.

It is used to identify differences between the expected infrastructure
configuration and the resources currently recorded or running in the
environment.

## What It Expects to Already Exist

The script expects:

- Terraform to be installed and available.
- A valid Terraform working directory.
- The Terraform configuration and modules to already exist.
- Terraform state to already be initialized and accessible.
- The required cloud credentials to be configured.
- Access to the infrastructure being inspected.
