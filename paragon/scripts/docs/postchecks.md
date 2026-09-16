# Post Checks

## What It Does

The `postchecks.sh` script performs post-deployment checks to verify that
the Kubapp environment is functioning correctly after infrastructure or
application changes.

It checks the resulting cluster and application state and reports
whether the expected resources and services are available.

## What It Expects to Already Exist

The script expects:

- A working Kubernetes cluster.
- `kubectl` to be installed and configured.
- The Kubapp infrastructure to already be deployed.
- The expected Kubernetes namespaces and workloads to already exist.
- ArgoCD and GitOps-managed applications to already be available when
  included in the post-deployment checks.
- Sufficient permissions to inspect the required Kubernetes resources.
