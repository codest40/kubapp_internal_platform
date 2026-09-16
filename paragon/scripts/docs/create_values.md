# Create Values

## What It Does

The `create_values.sh` script generates the Helm values configuration
required by a Kubapp service from its deployment artifact.

It prepares the service-specific values used by the GitOps deployment
process, allowing the generated configuration to be consumed by the
service's Helm deployment.

## What It Expects to Already Exist

The script expects:

- Bash to be available.
- The required command-line tools used by the script to be installed.
- A valid service artifact/configuration as input.
- The service's GitOps directory and related configuration to already
  exist.
- The required environment and service metadata needed to generate the
  values configuration.
