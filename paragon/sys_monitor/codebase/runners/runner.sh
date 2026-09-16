#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[CODEBASE RUNNER] $1"
}

line() {
    printf '%*s\n' "${1:-70}" '' | tr ' ' "${2:--}"
}

log "Starting KubApp SysMonitor codebase pipeline"

# ============================================================
# STEP 1: Discovery
# ============================================================
line
log "Running discovery"
bash "$BASE_DIR/discovery.sh" || log "discovery failed (non-blocking)"

# ============================================================
# STEP 2: Drift
# ============================================================
line
log "Running drift analysis"
bash "$BASE_DIR/drift.sh" || log "drift failed (non-blocking)"

# ============================================================
# STEP 3: Architecture
# ============================================================
line
log "Running architecture checks"
bash "$BASE_DIR/architecture.sh" || log "architecture failed (non-blocking)"

# ============================================================
# STEP 4: Filesystem
# ============================================================
line
log "Running filesystem collection"
bash "$BASE_DIR/filesystem.sh" || log "filesystem failed (non-blocking)"

# ============================================================
# STEP 2: Fs Drift
# ============================================================
line
log "Running filesystem drift analysis"
bash "$BASE_DIR/filesystem_drift.sh" || log "fs drift failed (non-blocking)"

# ============================================================
# STEP 4: Security
# ============================================================
line
log "Running security checks"
bash "$BASE_DIR/security.sh" || log "security failed (non-blocking)"

# ============================================================
# STEP 5: Validation
# ============================================================
line
log "Running validation checks"
bash "$BASE_DIR/validation.sh" || log "validation failed (non-blocking)"

# ============================================================
# STEP 6: METRICS
# ============================================================
line
log "Generating Prometheus metrics"
bash "$BASE_DIR/metrics.sh"

line
log "Pipeline completed"
