# Setup ArgoCD

## What It Does

The `setup_argocd.sh` script installs and prepares ArgoCD in the Kubernetes
cluster for Kubapp's GitOps deployment workflow.

It establishes the ArgoCD components required for applications to be
managed and reconciled from the Git repository.

## What It Expects to Already Exist

The script expects:

- A working Kubernetes cluster.
- `kubectl` to be installed and configured.
- The `argocd` CLI to be available if used by the script.
- The required ArgoCD manifests or installation configuration to already
  exist.
- Sufficient Kubernetes permissions to install and configure ArgoCD.
- The target cluster context to be correctly selected.
