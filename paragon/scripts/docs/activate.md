# Activate

## What It Does

The `activate.sh` script runs the Kubapp activation pipeline for an
environment.

It:

- Runs environment validation.
- Encrypts the environment secrets.
- Validates the GitOps configuration.
- Stages the repository changes.
- Creates a commit for the activation.
- Pushes the changes to the Git repository.
- Rebases and retries the push if the remote repository has changed.

The script can also skip the push when the user declines the confirmation
prompt.

## What It Expects to Already Exist

The script expects:

- A working Git repository.
- The required `validate.sh` script.
- The required `encrypt_secrets.sh` script.
- The required `validate_gitops.sh` script.
- Git configured with access to the remote repository.
- The required environment configuration and secrets files.
- The required GitOps configuration for the selected environment.

The environment defaults to `dev` but can be provided as the first
argument.

```bash
./scripts/activate.sh dev
