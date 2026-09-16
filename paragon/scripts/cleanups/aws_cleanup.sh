#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# AWS Resource Cleanup Script
# ==========================================================
# Purpose:
#   Safely checks for and deletes AWS resources by name/ID.
#
# Supported Resources:
#   - EC2 Instance
#   - Security Group
#   - IAM Role
#   - IAM Policy
#   - S3 Bucket
#   - CloudWatch Log Group
#   - ACM Certificate
#   - Route53 Hosted Zone
#   - ECR Repository
#   - Load Balancer (ALB/NLB)
#   - Target Group
#   - Launch Template
#
# Usage:
#   ./aws-cleanup.sh ec2-instance my-instance
#   ./aws-cleanup.sh security-group my-sg
#   ./aws-cleanup.sh iam-role my-role
#   ./aws-cleanup.sh s3-bucket my-bucket
#
# Requirements:
#   - AWS CLI configured
#   - jq installed
# ==========================================================

RESOURCE_TYPE="${1:-}"
RESOURCE_NAME="${2:-}"

AWS_REGION="${AWS_REGION:-us-east-1}"

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

error() {
  echo "[ERROR] $*" >&2
}

usage() {
  cat <<EOF
Usage:
  $0 <resource-type> <resource-name-or-id>

Resource Types:
  ec2-instance      EC2 Name tag
  security-group    Security Group name
  iam-role          IAM role name
  iam-policy        IAM policy name
  s3-bucket         Bucket name
  log-group         Log group name
  acm-cert          Certificate ARN
  route53-zone      Hosted zone name
  ecr-repo          Repository name
  load-balancer     Load balancer name
  target-group      Target group name
  launch-template   Launch template name
  eni               Network Interface ID
EOF
  exit 1
}

confirm_delete() {
  read -rp "Delete '$RESOURCE_NAME'? (yes/no): " ans
  ans="${ans,,}"
  [[ "$ans" == "yes" || "$ans" == "y" ]]
}

delete_ec2_instance() {
  local instance_id
  instance_id=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters \
      "Name=tag:Name,Values=$RESOURCE_NAME" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

  [[ -z "$instance_id" || "$instance_id" == "None" ]] && {
    warn "EC2 instance not found."
    return
  }

  log "Found EC2 instance: $instance_id"

  if confirm_delete; then
    aws ec2 terminate-instances \
      --region "$AWS_REGION" \
      --instance-ids "$instance_id" >/dev/null
    log "Termination initiated."
  fi
}

delete_security_group() {
  local sg_id
  sg_id=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=group-name,Values=$RESOURCE_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

  [[ -z "$sg_id" || "$sg_id" == "None" ]] && {
    warn "Security group not found."
    return
  }

  log "Found Security Group: $sg_id"

  if confirm_delete; then
    aws ec2 delete-security-group \
      --region "$AWS_REGION" \
      --group-id "$sg_id"
    log "Deleted security group."
  fi
}

delete_iam_role() {
  local role="$RESOURCE_NAME"

  aws iam get-role --role-name "$role" >/dev/null 2>&1 || {
    warn "IAM role not found."
    return
  }

  log "Found IAM role: $role"

  if confirm_delete; then
    # Detach managed policies
    aws iam list-attached-role-policies \
      --role-name "$role" \
      --query 'AttachedPolicies[].PolicyArn' \
      --output text | tr '\t' '\n' | while read -r arn; do
        [[ -n "$arn" ]] && aws iam detach-role-policy \
          --role-name "$role" \
          --policy-arn "$arn"
      done

    # Delete inline policies
    aws iam list-role-policies \
      --role-name "$role" \
      --query 'PolicyNames[]' \
      --output text | tr '\t' '\n' | while read -r policy; do
        [[ -n "$policy" ]] && aws iam delete-role-policy \
          --role-name "$role" \
          --policy-name "$policy"
      done

    # Remove from instance profiles
    aws iam list-instance-profiles-for-role \
      --role-name "$role" \
      --query 'InstanceProfiles[].InstanceProfileName' \
      --output text | tr '\t' '\n' | while read -r profile; do
        [[ -n "$profile" ]] && aws iam remove-role-from-instance-profile \
          --instance-profile-name "$profile" \
          --role-name "$role"
      done

    aws iam delete-role --role-name "$role"
    log "Deleted IAM role."
  fi
}

delete_iam_policy() {
  local policy_arn
  policy_arn=$(aws iam list-policies --scope Local \
    --query "Policies[?PolicyName=='$RESOURCE_NAME'].Arn" \
    --output text)

  [[ -z "$policy_arn" || "$policy_arn" == "None" ]] && {
    warn "IAM policy not found."
    return
  }

  log "Found IAM policy: $policy_arn"

  if confirm_delete; then
    # Delete non-default versions
    aws iam list-policy-versions \
      --policy-arn "$policy_arn" \
      --query 'Versions[?IsDefaultVersion==`false`].VersionId' \
      --output text | tr '\t' '\n' | while read -r version; do
        [[ -n "$version" ]] && aws iam delete-policy-version \
          --policy-arn "$policy_arn" \
          --version-id "$version"
      done

    aws iam delete-policy --policy-arn "$policy_arn"
    log "Deleted IAM policy."
  fi
}

delete_s3_bucket() {
  local bucket="$RESOURCE_NAME"

  aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1 || {
    warn "S3 bucket not found."
    return
  }

  log "Found S3 bucket: $bucket"

  if confirm_delete; then
    aws s3 rm "s3://$bucket" --recursive || true
    aws s3api delete-bucket --bucket "$bucket"
    log "Deleted bucket."
  fi
}

delete_log_group() {
  local name="$RESOURCE_NAME"

  aws logs describe-log-groups \
    --log-group-name-prefix "$name" \
    --query 'logGroups[?logGroupName==`'"$name"'`].logGroupName' \
    --output text | grep -q . || {
      warn "Log group not found."
      return
    }

  log "Found log group: $name"

  if confirm_delete; then
    aws logs delete-log-group --log-group-name "$name"
    log "Deleted log group."
  fi
}

delete_acm_cert() {
  local arn="$RESOURCE_NAME"

  aws acm describe-certificate \
    --certificate-arn "$arn" >/dev/null 2>&1 || {
      warn "Certificate not found."
      return
    }

  log "Found ACM certificate."

  if confirm_delete; then
    aws acm delete-certificate --certificate-arn "$arn"
    log "Deleted certificate."
  fi
}

delete_route53_zone() {
  local zone_id
  zone_id=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='${RESOURCE_NAME}.'].Id" \
    --output text | sed 's|/hostedzone/||')

  [[ -z "$zone_id" || "$zone_id" == "None" ]] && {
    warn "Hosted zone not found."
    return
  }

  log "Found Hosted Zone: $zone_id"

  if confirm_delete; then
    warn "Hosted zones must be empty before deletion."
    aws route53 delete-hosted-zone --id "$zone_id"
    log "Deleted hosted zone."
  fi
}

delete_ecr_repo() {
  local repo="$RESOURCE_NAME"

  aws ecr describe-repositories \
    --repository-names "$repo" >/dev/null 2>&1 || {
      warn "ECR repository not found."
      return
    }

  log "Found ECR repository: $repo"

  if confirm_delete; then
    aws ecr delete-repository \
      --repository-name "$repo" \
      --force
    log "Deleted repository."
  fi
}

delete_load_balancer() {
  local arn
  arn=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?LoadBalancerName=='$RESOURCE_NAME'].LoadBalancerArn" \
    --output text)

  [[ -z "$arn" || "$arn" == "None" ]] && {
    warn "Load balancer not found."
    return
  }

  log "Found Load Balancer."

  if confirm_delete; then
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn"
    log "Deleted load balancer."
  fi
}

delete_target_group() {
  local arn
  arn=$(aws elbv2 describe-target-groups \
    --query "TargetGroups[?TargetGroupName=='$RESOURCE_NAME'].TargetGroupArn" \
    --output text)

  [[ -z "$arn" || "$arn" == "None" ]] && {
    warn "Target group not found."
    return
  }

  log "Found Target Group."

  if confirm_delete; then
    aws elbv2 delete-target-group --target-group-arn "$arn"
    log "Deleted target group."
  fi
}

delete_launch_template() {
  aws ec2 describe-launch-templates \
    --launch-template-names "$RESOURCE_NAME" >/dev/null 2>&1 || {
      warn "Launch template not found."
      return
    }

  log "Found Launch Template: $RESOURCE_NAME"

  if confirm_delete; then
    aws ec2 delete-launch-template \
      --launch-template-name "$RESOURCE_NAME"
    log "Deleted launch template."
  fi
}

delete_eni() {
  local eni_id="$RESOURCE_NAME"

  # Verify ENI exists
  aws ec2 describe-network-interfaces \
    --network-interface-ids "$eni_id" >/dev/null 2>&1 || {
      warn "ENI not found: $eni_id"
      return
    }

  # Gather attachment info
  local attachment_id status instance_id
  attachment_id=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$eni_id" \
    --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
    --output text)

  status=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$eni_id" \
    --query 'NetworkInterfaces[0].Status' \
    --output text)

  instance_id=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$eni_id" \
    --query 'NetworkInterfaces[0].Attachment.InstanceId' \
    --output text)

  log "Found ENI: $eni_id"
  log "Status: $status"

  if [[ "$attachment_id" != "None" && -n "$attachment_id" ]]; then
    log "Attached to instance: ${instance_id:-unknown}"
    log "Attachment ID: $attachment_id"
  else
    log "ENI is not attached."
  fi

  if confirm_delete; then
    # Detach if attached
    if [[ "$attachment_id" != "None" && -n "$attachment_id" ]]; then
      log "Detaching ENI..."
      aws ec2 detach-network-interface \
        --attachment-id "$attachment_id"

      # Wait until available
      log "Waiting for ENI to become available..."
      aws ec2 wait network-interface-available \
        --network-interface-ids "$eni_id"
    fi

    # Delete ENI
    log "Deleting ENI..."
    aws ec2 delete-network-interface \
      --network-interface-id "$eni_id"

    log "Deleted ENI: $eni_id"
  fi
}

main() {
  [[ -z "$RESOURCE_TYPE" || -z "$RESOURCE_NAME" ]] && usage

  case "$RESOURCE_TYPE" in
    ec2-instance)     delete_ec2_instance ;;
    security-group)   delete_security_group ;;
    iam-role)         delete_iam_role ;;
    iam-policy)       delete_iam_policy ;;
    s3-bucket)        delete_s3_bucket ;;
    log-group)        delete_log_group ;;
    acm-cert)         delete_acm_cert ;;
    route53-zone)     delete_route53_zone ;;
    ecr-repo)         delete_ecr_repo ;;
    load-balancer)    delete_load_balancer ;;
    target-group)     delete_target_group ;;
    launch-template)  delete_launch_template ;;
    eni) delete_eni ;;
    *)
      error "Unsupported resource type: $RESOURCE_TYPE"
      usage
      ;;
  esac
}

main "$@"

