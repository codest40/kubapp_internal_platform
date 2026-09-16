#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT_DIR" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi

source "$ROOT_DIR/reuse.sh"
BOOT_DIR="$ROOT/iac/boot"
INFRA_DIR="$ROOT/iac/infra"
K8S_DIR="$ROOT/iac/k8s"
MAN_DIR="$ROOT/iac/manifests"
ENVIRONMENTS=("dev" "prod")

log() {
  printf '[SUPPLIER] %s\n' "$1"
}

fail() {
  printf '[SUPPLIER] ERROR: %s\n' "$1" >&2
  exit 1
}

command -v terraform >/dev/null 2>&1 || fail "terraform is not installed"

[[ -d "$BOOT_DIR" ]] || fail "Boot directory not found: $BOOT_DIR"
[[ -d "$INFRA_DIR" ]] || fail "Infra directory not found: $INFRA_DIR"
[[ -d "$K8S_DIR" ]] || fail "K8s directory not found: $K8S_DIR"
[[ -d "$MAN_DIR" ]] || fail "Manifests directory not found: $MAN_DIR"

log "Reading bootstrap outputs..."

STATE_BUCKET="$(terraform -chdir="$BOOT_DIR" output -raw state_bucket_name 2>/dev/null || true)"
REGION="$(terraform -chdir="$BOOT_DIR" output -raw region 2>/dev/null || true)"

[[ -n "$STATE_BUCKET" ]] || fail "state_bucket_name is unavailable from iac/boot"
[[ -n "$REGION" ]] || fail "region is unavailable from iac/boot"

log "State bucket: $STATE_BUCKET"
log "Region: $REGION"

for ENV in "${ENVIRONMENTS[@]}"; do
  INFRA_ENV_DIR="$INFRA_DIR/envs/$ENV"
  K8S_ENV_DIR="$K8S_DIR/envs/$ENV"
  MAN_ENV_DIR="$MAN_DIR/envs/$ENV"

  mkdir -p "$INFRA_ENV_DIR" "$K8S_ENV_DIR" "$MAN_ENV_DIR"

  cat > "$INFRA_ENV_DIR/backend.hcl" <<EOF
bucket       = "$STATE_BUCKET"
key          = "$ENV/infra/terraform.tfstate"
region       = "$REGION"
use_lockfile = true
encrypt      = true
EOF

  cat > "$K8S_ENV_DIR/backend.hcl" <<EOF
bucket       = "$STATE_BUCKET"
key          = "$ENV/k8s/terraform.tfstate"
region       = "$REGION"
use_lockfile = true
encrypt      = true
EOF

  cat > "$MAN_ENV_DIR/backend.hcl" <<EOF
bucket       = "$STATE_BUCKET"
key          = "$ENV/manifests/terraform.tfstate"
region       = "$REGION"
use_lockfile = true
encrypt      = true
EOF

  log "Generated infra/$ENV/backend.hcl"
  log "Generated k8s/$ENV/backend.hcl"
  log "Generated manifests/$ENV/backend.hcl"

done

log "Backend configuration generation complete."

