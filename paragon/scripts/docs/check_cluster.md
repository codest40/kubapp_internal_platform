# Check Cluster

## What It Does

The `check_cluster.sh` script verifies that the Kubernetes cluster and
ArgoCD components are ready.

It:

- Checks that the `cluster-readiness` ConfigMap exists.
- Reads the cluster readiness status and cluster name.
- Waits for the ArgoCD server deployment to become ready.
- Waits for the ArgoCD repo-server deployment to become ready.
- Waits for the ArgoCD application controller StatefulSet to become ready.
- Reports that the system is ready when all checks pass.

## What It Expects to Already Exist

The script expects:

- A working Kubernetes cluster.
- `kubectl` configured to access the cluster.
- `jq` to be installed.
- The `cluster-readiness` ConfigMap in the `kube-system` namespace.
- ArgoCD installed in the `argocd` namespace.
- The ArgoCD server, repo-server, and application-controller resources
  to already exist.
- Sufficient Kubernetes permissions to read these resources.
