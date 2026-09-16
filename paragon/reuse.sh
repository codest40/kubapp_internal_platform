#!/bin/bash


ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    return 1 2>/dev/null || exit 1
fi

export ROOT

SCRIPTS_DIR="$ROOT/scripts"
GITOPS_DIR="$ROOT/gitops"
IAC_DIR="$ROOT/iac"
APPS_DIR="$ROOT/docker"
DOCS_DIR="$ROOT/docs"
SYS_MONITOR_DIR="$ROOT/sys_monitor"

export SCRIPTS_DIR
export GITOPS_DIR
export IAC_DIR
export APPS_DIR
export DOCS_DIR
export SYS_MONITOR_DIR
