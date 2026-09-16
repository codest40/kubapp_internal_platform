# Delete ArgoCD

## What It Does

The `del_argocd.sh` script removes the ArgoCD installation and its related
Kubernetes resources from the cluster.

It is used when ArgoCD needs to be completely removed as part of cluster
cleanup or infrastructure teardown.

## What It Expects to Already Exist

The script expects:

- A working Kubernetes cluster.
- `kubectl` to be installed and configured.
- Access to the target cluster with sufficient permissions to delete
  ArgoCD resources.
- ArgoCD to already be installed in the cluster.
- The ArgoCD namespace and related resources to exist.

