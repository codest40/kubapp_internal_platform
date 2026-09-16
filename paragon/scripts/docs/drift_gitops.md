# Drift GitOps

## What It Does

The `drift_gitops.sh` script checks the GitOps-managed Kubernetes
resources for configuration drift between the declared Git state and the
state currently running in the cluster.

It is used to identify resources that may have been changed manually or
otherwise differ from the configuration stored in Git.

## What It Expects to Already Exist

The script expects:

- A working Kubernetes cluster.
- `kubectl` to be installed and configured.
- ArgoCD to already be installed and running.
- The Kubapp applications to already be managed by ArgoCD.
- The GitOps configuration and application definitions to already exist.
- Sufficient permissions to inspect the relevant Kubernetes and ArgoCD
  resources.
