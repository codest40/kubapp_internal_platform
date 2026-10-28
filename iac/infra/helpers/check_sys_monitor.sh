#!/bin/bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
    if [[ "$PWD" != */iac/infra/helpers ]]; then
        echo "[ERROR] Unable to determine project root." >&2
        exit 1
    fi
    ROOT="${PWD%/iac/infra/helpers}"
fi

SYS_MONITOR="$ROOT/sys_monitor/cloud/aws/store"
STATUS_FILE="$SYS_MONITOR/status"

if [[ ! -s "$STATUS_FILE" ]]; then
    echo "[ERROR] Missing or empty status file: $STATUS_FILE" >&2
    exit 1
fi

status="$(<"$STATUS_FILE")"
case "$status" in
    active)
        echo "true"
        ;;
    inactive)
        echo "false"
        ;;
    *)
        echo "[ERROR] Invalid sys_monitor status: $status" >&2
        exit 1
        ;;
esac
