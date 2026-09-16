# Cleanup Logs

## What It Does

The `cleanup_logs.sh` script removes orphaned AWS CloudWatch log groups
for a specific Kubapp environment.

It:

- Finds CloudWatch log groups matching the project and environment.
- Skips Terraform-related log groups.
- Skips log groups that have a configured retention period.
- Deletes only log groups that are considered never-expiring.
- Refuses to run against `prod` or `production`.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed and configured.
- Permissions to list and delete CloudWatch log groups.
- `ENV` to be set.
- `AWS_REGION` to be set if the default `us-east-1` is not appropriate.
- The relevant Kubapp CloudWatch log groups to use the expected
  `<PROJECT>-<ENV>` naming pattern.

`PROJECT` is optional and defaults to `kubapp`.

Example:

```bash
ENV=dev ./scripts/cleanup_logs.sh
