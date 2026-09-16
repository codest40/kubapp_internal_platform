# Setup SOPS

## What It Does

The `setup_sops.sh` script prepares SOPS for Kubapp's secret encryption
workflow.

It configures the required SOPS encryption setup so secrets can be
encrypted and decrypted by the Kubapp scripts and GitOps workflows.

## What It Expects to Already Exist

The script expects:

- SOPS to be installed.
- The required encryption configuration to be available.
- The required SOPS/AGE key or key configuration to already exist or be
  supplied by the environment.
- The Kubapp repository and its SOPS configuration files to already exist.
- The user or execution environment to have access to the required
  encryption key material.
