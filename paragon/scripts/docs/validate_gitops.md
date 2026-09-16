# Validate GitOps

## What It Does

The `validate_gitops.sh` script validates the Kubapp GitOps configuration
before it is committed or deployed.

It checks that the GitOps configuration is structurally valid and ready
for ArgoCD to consume.

## What It Expects to Already Exist

The script expects:

- The Kubapp GitOps directory structure to already exist.
- The required application and service configuration files to be present.
- The required Kubernetes and GitOps manifests to already exist.
- `kubectl` and any other command-line tools used by the validation
  checks to be installed.
- A valid GitOps configuration that can be inspected and validated.
- ArgoCD-related configuration to already exist when included in the
  validation checks.
