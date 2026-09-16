# Encrypt Secrets

## What It Does

The `encrypt_secrets.sh` script encrypts Kubernetes service secrets before
they are stored or used by the Kubapp GitOps workflow.

It ensures that sensitive secret values are processed through SOPS rather
than being stored as plain-text secrets in the Git repository.

## What It Expects to Already Exist

The script expects:

- `sops` to be installed.
- The required SOPS encryption configuration to exist.
- The required encryption key to be available.
- The target environment configuration to already exist.
- The service secret files to exist in the expected GitOps locations.
- The user or execution environment to have permission to access the
  source secret files.

The environment is provided as the first argument.

```bash
./scripts/encrypt_secrets.sh dev
