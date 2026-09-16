# Verify Cleanup

## What It Does

The `verify_cleanup.sh` script verifies that the Kubapp cleanup process
has successfully removed the expected Kubernetes and AWS resources.

It is used as a final validation step after cleanup to identify any
resources that may still remain.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed and configured when AWS resources are checked.
- `kubectl` to be installed and configured when Kubernetes resources are
  checked.
- Valid AWS credentials and permissions.
- Access to the target Kubernetes cluster.
- The environment or cluster being checked to already have gone through
  the cleanup process.
- Any required environment variables or resource identifiers to already
  be available.
