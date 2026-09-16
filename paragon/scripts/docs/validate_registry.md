# Validate Registry

## What It Does

The `validate_registry.sh` script validates the container image registry
configuration used by Kubapp.

It checks that the required registry configuration and container image
references are valid before they are used by the deployment workflow.

## What It Expects to Already Exist

The script expects:

- The required container registry to already exist.
- The registry configuration to already be available.
- AWS credentials and permissions when validating an AWS ECR registry.
- The required registry, repository, or image information to be available.
- The command-line tools used by the validation checks to be installed.
