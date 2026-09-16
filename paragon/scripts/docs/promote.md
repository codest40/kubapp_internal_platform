# Promote

## What It Does

The `promote.sh` script promotes a Kubapp application or configuration
from one environment to another as part of the deployment workflow.

It prepares the required GitOps changes for the target environment so the
application can be deployed through the normal GitOps process.

## What It Expects to Already Exist

The script expects:

- The source and target environments to already be configured.
- The application's GitOps configuration to already exist.
- The required service or deployment configuration to already exist.
- Git to be installed and the repository to be available.
- The GitOps repository to be in a valid state for the promotion.
- Any required environment variables or arguments to be provided.
- ArgoCD and the target Kubernetes environment to already be available
  when the promotion is intended to result in an immediate deployment.
