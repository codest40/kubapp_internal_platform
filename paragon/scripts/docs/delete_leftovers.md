# Delete Leftovers

## What It Does

The `delete_leftovers.sh` script removes AWS resources that remain after
the main infrastructure cleanup.

It is used as a final cleanup step to identify and delete resources that
were not removed during the normal Terraform or Kubernetes teardown
process.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed and configured.
- The required AWS credentials and permissions.
- The target AWS region to be configured.
- The cluster, VPC, or resource identifiers required by the script to
  already be available.
- Any required environment variables used by the cleanup workflow to be
  set.
