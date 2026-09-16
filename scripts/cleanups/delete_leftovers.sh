#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PRODUCTION ENI CLEANUP ENGINE (ORPHAN-BASED DELETION)
# ============================================================

ENV="${ENV:?ENV required}"
REGION="${AWS_REGION:?AWS_REGION required}"
VPC_ID="${VPC_ID:?VPC_ID required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
DRY_RUN="${DRY_RUN:-true}"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

awsq(){
  aws "$@" --region "$REGION" --no-cli-pager
}

run(){
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY_RUN] $*"
  else
    eval "$@"
  fi
}

[[ "$ENV" == "prod" ]] && { log "BLOCKED PROD"; exit 1; }

# ============================================================
# STEP 1: LIST ENIs
# ============================================================

log "STEP 1: LIST ENIs"
log "VPC=$VPC_ID REGION=$REGION CLUSTER=$CLUSTER_NAME"

enis=$(awsq ec2 describe-network-interfaces \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text 2>/dev/null || true)

[[ -z "$enis" ]] && { log "NO ENIs FOUND"; exit 0; }

log "ENIs FOUND:"
for eni in $enis; do
  log "FOUND ENI: $eni"
done

# ============================================================
# STEP 2: PROCESS ENIs (ORPHAN RULE ENGINE)
# ============================================================

for eni in $enis; do

  log "---- ENI START: $eni ----"

  json=$(awsq ec2 describe-network-interfaces \
    --network-interface-ids "$eni" \
    --output json 2>/dev/null || true)

  if [[ -z "$json" || "$json" == "null" ]]; then
    log "ENI DISAPPEARED (already deleted) → SKIP"
    continue
  fi

  desc=$(echo "$json" | jq -r '.NetworkInterfaces[0].Description // ""')
  status=$(echo "$json" | jq -r '.NetworkInterfaces[0].Status // ""')
  attachment_id=$(echo "$json" | jq -r '.NetworkInterfaces[0].Attachment.AttachmentId // ""')
  requester=$(echo "$json" | jq -r '.NetworkInterfaces[0].RequesterId // ""')

  log "DESC=$desc"
  log "STATUS=$status"
  log "REQUESTER=$requester"
  log "ATTACHMENT=$attachment_id"

  # =========================================================
  # HARD PROTECTION RULES (NEVER DELETE)
  # =========================================================

  if [[ "$requester" == "amazon-vpc" ]]; then
    log "SKIP CORE AWS VPC ENI"
    continue
  fi

  if [[ "$desc" == *"NAT Gateway"* ]]; then
    log "SKIP NAT"
    continue
  fi

  if [[ "$desc" == *"EFS"* || "$desc" == *"efs"* ]]; then
    log "SKIP EFS"
    continue
  fi

  # =========================================================
  # MAIN ORPHAN RULE (THIS IS WHAT YOU WANT)
  # =========================================================

  if [[ "$status" == "available" ]]; then

    if [[ -z "$attachment_id" || "$attachment_id" == "None" || "$attachment_id" == "null" ]]; then

      log "ORPHAN DETECTED → SAFE DELETE"

      run aws ec2 delete-network-interface \
        --network-interface-id "$eni"

    else
      log "HAS ATTACHMENT → SKIP"
    fi

  else
    log "NOT AVAILABLE → SKIP"
  fi

  log "---- ENI END ----"
done

log "ENGINE COMPLETE"
