# AWS Cleanup

## What It Does

The `aws_cleanup.sh` script safely finds and deletes specific AWS resources
by resource type and name.

It supports cleanup of:

- EC2 instances
- Security groups
- IAM roles
- IAM policies
- S3 buckets
- CloudWatch log groups
- ACM certificates
- Route53 hosted zones
- ECR repositories
- Application/Network Load Balancers
- Target groups
- Launch templates
- Elastic Network Interfaces (ENIs)

Before deleting a resource, the script asks for confirmation.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed.
- AWS credentials to be configured.
- Permissions to inspect and delete the requested AWS resources.
- `jq` to be installed.
- A valid AWS region, using `AWS_REGION` when one is not explicitly
  configured.

The resource type and resource name must be provided when running the
script.

```bash
./scripts/aws_cleanup.sh <resource-type> <resource-name>
