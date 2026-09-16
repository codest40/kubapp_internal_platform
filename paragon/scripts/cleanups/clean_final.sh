#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# force_cleanup.sh
#
# Purpose:
#   Deletes any AWS resources that may remain after EKS/VPC
#   teardown, including orphaned resources.
#
# Scope:
#   - Target Groups
#   - ALB/NLB
#   - Classic ELB
#   - Auto Scaling Groups
#   - EC2 Instances
#   - ENIs
#   - NAT Gateways
#   - EBS Volumes
#   - EFS File Systems
#   - Security Groups
#   - Subnets
#   - Route Tables
#   - Internet Gateways
#   - VPC
#
# Usage:
#   export CLUSTER_NAME=my-cluster
#   export AWS_REGION=us-east-1
#   export VPC_ID=vpc-xxxxxxxx   # optional
#   ./scripts/force_cleanup.sh
#
# Notes:
#   - Safe to rerun.
#   - Ignores "not found" errors.
#   - Uses both cluster name and VPC relationships.
# ============================================================

CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
REGION="${AWS_REGION:?AWS_REGION required}"
VPC_ID="${VPC_ID:-}"

if [[ -z "${LEFTOVERS:-}" ]]; then
  echo "❌ LEFTOVERS is not set in environment"
fi

if [[ "${LEFTOVERS}" != "true" ]]; then
  echo "✅ No Leftovers Remaining. Account Is Clean."
  exit 0
fi

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERROR] $*"; }

run() {
  "$@" >/dev/null 2>&1 || true
}

header() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Missing dependency: $1"
    exit 1
  }
}

require aws
require jq

# ============================================================
# Resolve VPC
# ============================================================

if [[ -z "$VPC_ID" ]]; then
  log "Resolving VPC from EKS cluster..."

  VPC_ID=$(
    aws eks describe-cluster \
      --name "$CLUSTER_NAME" \
      --region "$REGION" \
      --query 'cluster.resourcesVpcConfig.vpcId' \
      --output text 2>/dev/null || true
  )

  if [[ -z "$VPC_ID" || "$VPC_ID" == "None" || "$VPC_ID" == "null" ]]; then
    warn "Could not resolve VPC from EKS."
    VPC_ID=""
  else
    log "Resolved VPC_ID=$VPC_ID"
  fi
else
  log "Using provided VPC_ID=$VPC_ID"
fi

# ============================================================
# Target Groups
# ============================================================

header "DELETE TARGET GROUPS"

aws elbv2 describe-target-groups \
  --region "$REGION" \
  --query 'TargetGroups[].{Name:TargetGroupName,Arn:TargetGroupArn,VpcId:VpcId}' \
  --output json |
jq -r --arg CLUSTER "$CLUSTER_NAME" --arg VPC "$VPC_ID" '
.[] |
select(
  (.Name | test($CLUSTER; "i") or test("^k8s-"))
  or
  ($VPC != "" and .VpcId == $VPC)
) |
.Arn
' |
while read -r arn; do
  [[ -n "$arn" ]] || continue
  log "Deleting target group: $arn"
  run aws elbv2 delete-target-group --target-group-arn "$arn" --region "$REGION"
done

# ============================================================
# ALB/NLB
# ============================================================

header "DELETE LOAD BALANCERS"

aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query 'LoadBalancers[].{Arn:LoadBalancerArn,Name:LoadBalancerName,VpcId:VpcId}' \
  --output json |
jq -r --arg CLUSTER "$CLUSTER_NAME" --arg VPC "$VPC_ID" '
.[] |
select(
  (.Name | test($CLUSTER; "i") or test("^k8s-"))
  or
  ($VPC != "" and .VpcId == $VPC)
) |
.Arn
' |
while read -r arn; do
  [[ -n "$arn" ]] || continue
  log "Deleting load balancer: $arn"
  run aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$REGION"
done

sleep 10

# ============================================================
# Classic ELB
# ============================================================

header "DELETE CLASSIC LOAD BALANCERS"

aws elb describe-load-balancers \
  --region "$REGION" \
  --query 'LoadBalancerDescriptions[].LoadBalancerName' \
  --output text |
tr '\t' '\n' |
{ grep -Ei "$CLUSTER_NAME|^k8s-" || true; } |
while read -r name; do
  [[ -n "$name" ]] || continue
  log "Deleting classic ELB: $name"
  run aws elb delete-load-balancer \
    --load-balancer-name "$name" \
    --region "$REGION"
done

# ============================================================
# Auto Scaling Groups
# ============================================================

header "DELETE AUTO SCALING GROUPS"

aws autoscaling describe-auto-scaling-groups \
  --region "$REGION" \
  --query 'AutoScalingGroups[].AutoScalingGroupName' \
  --output text |
tr '\t' '\n' |
grep -Ei "$CLUSTER_NAME" || true |
while read -r asg; do
  [[ -n "$asg" ]] || continue
  log "Scaling ASG to zero: $asg"
  run aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$asg" \
    --min-size 0 \
    --max-size 0 \
    --desired-capacity 0 \
    --region "$REGION"

  log "Deleting ASG: $asg"
  run aws autoscaling delete-auto-scaling-group \
    --auto-scaling-group-name "$asg" \
    --force-delete \
    --region "$REGION"
done

# ============================================================
# EC2 Instances
# ============================================================

header "TERMINATE EC2 INSTANCES"

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text |
  tr '\t' '\n' |
  while read -r id; do
    [[ -n "$id" ]] || continue
    log "Terminating instance: $id"
    run aws ec2 terminate-instances \
      --instance-ids "$id" \
      --region "$REGION"
  done
fi

# ============================================================
# NAT Gateways
# ============================================================

header "DELETE NAT GATEWAYS"

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-nat-gateways \
    --region "$REGION" \
    --filter "Name=vpc-id,Values=$VPC_ID" \
    --query 'NatGateways[?State!=`deleted`].NatGatewayId' \
    --output text |
  tr '\t' '\n' |
  while read -r nat; do
    [[ -n "$nat" ]] || continue
    log "Deleting NAT Gateway: $nat"
    run aws ec2 delete-nat-gateway \
      --nat-gateway-id "$nat" \
      --region "$REGION"
  done
fi

# ============================================================
# ENIs
# ============================================================

header "DELETE NETWORK INTERFACES"

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' \
    --output text |
  tr '\t' '\n' |
  while read -r eni; do
    [[ -n "$eni" ]] || continue
    log "Deleting ENI: $eni"
    run aws ec2 delete-network-interface \
      --network-interface-id "$eni" \
      --region "$REGION"
  done
fi

# ============================================================
# EBS Volumes
# ============================================================

header "DELETE AVAILABLE EBS VOLUMES"

aws ec2 describe-volumes \
  --region "$REGION" \
  --filters "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' \
  --output text |
tr '\t' '\n' |
while read -r vol; do
  [[ -n "$vol" ]] || continue
  log "Deleting volume: $vol"
  run aws ec2 delete-volume \
    --volume-id "$vol" \
    --region "$REGION"
done

# ============================================================
# EFS
# ============================================================

header "DELETE EFS FILE SYSTEMS"

aws efs describe-file-systems \
  --region "$REGION" \
  --query 'FileSystems[].FileSystemId' \
  --output text |
tr '\t' '\n' |
while read -r fs; do
  [[ -n "$fs" ]] || continue

  log "Deleting mount targets for EFS: $fs"

  aws efs describe-mount-targets \
    --file-system-id "$fs" \
    --region "$REGION" \
    --query 'MountTargets[].MountTargetId' \
    --output text |
  tr '\t' '\n' |
  while read -r mt; do
    [[ -n "$mt" ]] || continue
    run aws efs delete-mount-target \
      --mount-target-id "$mt" \
      --region "$REGION"
  done

  log "Deleting EFS: $fs"
  run aws efs delete-file-system \
    --file-system-id "$fs" \
    --region "$REGION"
done

# ============================================================
# SECURITY GROUPS
# ============================================================

header "DELETE SECURITY GROUPS"

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text |
  tr '\t' '\n' |
  while read -r sg; do
    [[ -n "$sg" ]] || continue
    log "Deleting security group: $sg"
    run aws ec2 delete-security-group \
      --group-id "$sg" \
      --region "$REGION"
  done
fi

# ============================================================
# SUBNETS
# ============================================================

header "DELETE SUBNETS"

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].SubnetId' \
    --output text |
  tr '\t' '\n' |
  while read -r subnet; do
    [[ -n "$subnet" ]] || continue
    log "Deleting subnet: $subnet"
    run aws ec2 delete-subnet \
      --subnet-id "$subnet" \
      --region "$REGION"
  done
fi

# ============================================================
# ROUTE TABLES
# ============================================================

header "DELETE ROUTE TABLES"

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
    --output text |
  tr '\t' '\n' |
  while read -r rt; do
    [[ -n "$rt" ]] || continue
    log "Deleting route table: $rt"
    run aws ec2 delete-route-table \
      --route-table-id "$rt" \
      --region "$REGION"
  done
fi

# ============================================================
# INTERNET GATEWAYS
# ============================================================

header "DELETE INTERNET GATEWAYS"

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-internet-gateways \
    --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[].InternetGatewayId' \
    --output text |
  tr '\t' '\n' |
  while read -r igw; do
    [[ -n "$igw" ]] || continue

    log "Detaching IGW: $igw"
    run aws ec2 detach-internet-gateway \
      --internet-gateway-id "$igw" \
      --vpc-id "$VPC_ID" \
      --region "$REGION"

    log "Deleting IGW: $igw"
    run aws ec2 delete-internet-gateway \
      --internet-gateway-id "$igw" \
      --region "$REGION"
  done
fi

# ============================================================
# VPC
# ============================================================

header "DELETE VPC"

if [[ -n "$VPC_ID" ]]; then
  log "Deleting VPC: $VPC_ID"
  run aws ec2 delete-vpc \
    --vpc-id "$VPC_ID" \
    --region "$REGION"
fi

echo
echo "=================================================="
echo "✅ FORCE CLEANUP COMPLETE"
echo "=================================================="

