# Create Secrets

## What It Does

The `create_secrets.sh` script creates or updates a Kubernetes Secret from
an encrypted SOPS secret file.

It:

- Reads service and namespace information from an artifact JSON file.
- Verifies that the artifact belongs to the `gitops/` directory.
- Locates the encrypted secret file for the service.
- Decrypts the secret using SOPS into a temporary file.
- Reads the secret values from the decrypted configuration.
- Generates a Kubernetes Secret manifest.
- Applies the Secret to the target namespace.
- Skips deployment when the service does not define secrets.

The decrypted secret data is handled through temporary files and is not
written back into the GitOps repository.

## What It Expects to Already Exist

The script expects:

- `jq` to be installed.
- `yq` to be installed.
- `sops` to be installed and configured with the required decryption key.
- `kubectl` to be installed and configured for the target cluster.
- A valid artifact JSON file under `gitops/`.
- The artifact to contain the required `service`, `context`, `namespace`,
  and `NO_SECRETS` fields.
- An encrypted `secrets.yaml`, `secrets.yml`, `secret.yaml`, or
  `secret.yml` file when `NO_SECRETS=false`.
- The target Kubernetes cluster to be accessible.

Usage:

```bash
./scripts/create_secrets.sh gitops/<service>/artifact.json
