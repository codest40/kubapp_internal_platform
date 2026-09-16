# Clean Cluster

## What It Does

The `clean_cluster.sh` script cleans Kubernetes application resources and
namespaces before infrastructure teardown.

It:

- Refuses to run when the current Kubernetes context appears to be
  production.
- Stops ArgoCD ApplicationSet and Application reconciliation first.
- Removes ArgoCD applications that could recreate resources during cleanup.
- Cleans application resources from non-system namespaces.
- Removes stuck resource finalizers when normal deletion hangs.
- Force-deletes remaining resources as a last resort.
- Deletes non-system namespaces after their resources are cleaned.
- Performs final checks for remaining ingress resources and namespaces.

The script is designed to prevent GitOps reconciliation and Kubernetes
finalizers from blocking cluster cleanup.

## What It Expects to Already Exist

The script expects:

- A working Kubernetes cluster.
- `kubectl` configured for the target cluster.
- Access to the cluster with sufficient permissions to delete and patch
  Kubernetes resources.
- ArgoCD resources to exist if ArgoCD cleanup is required.
- The `TF_CREATED_NS` environment variable to be set when Terraform-managed
  namespaces need to be protected from deletion.

The script intentionally skips Kubernetes system namespaces and the
`argocd` namespace during the main namespace cleanup loop.
