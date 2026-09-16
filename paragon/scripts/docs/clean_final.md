# Clean Final

## What It Does

The `clean_final.sh` script performs final AWS cleanup after the EKS and
VPC infrastructure has been torn down.

It looks for and removes leftover AWS resources associated with the
Kubapp cluster and its VPC, including:

- Target groups
- Application/Network Load Balancers
- Classic Load Balancers
- Auto Scaling Groups
- EC2 instances
- Elastic Network Interfaces (ENIs)
- NAT gateways
- Available EBS volumes
- EFS file systems
- Security groups
- Subnets
- Route tables
- Internet gateways
- The VPC itself

The script only performs the cleanup when `LEFTOVERS=true`. This provides
a safety gate against accidentally running the final cleanup when there
are no known leftovers.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed and configured.
- `jq` to be installed.
- `CLUSTER_NAME` to be set.
- `AWS_REGION` to be set.
- `LEFTOVERS=true` when cleanup should actually be performed.
- The target AWS resources to be accessible with sufficient permissions.
- `VPC_ID` to be set when the VPC is already known; otherwise the script
  attempts to resolve it from the EKS cluster.

Example:

```bash
CLUSTER_NAME=my-cluster \
AWS_REGION=us-east-1 \
LEFTOVERS=true \
./scripts/clean_final.sh
