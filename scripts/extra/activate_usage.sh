#!/usr/bin/env bash

show_activate_usage() {
    cat <<'EOF'

KUBAPP ACTIVATION
=================

Usage:
  ./scripts/activate.sh [ENV]

Arguments:
  ENV                 Target environment (default: dev)

Environment variables:
  ACTION              Git action (default: rebase)
                      Supported: rebase, diagnose

  PUSH                Skip push confirmation when true or yes.
                      Default: false

  APPS                Run application validation when true or yes.
                      Default: false

Examples:
  ./scripts/activate.sh

  ./scripts/activate.sh dev

  PUSH=true ./scripts/activate.sh dev

  APPS=true ./scripts/activate.sh dev

  PUSH=true APPS=true ./scripts/activate.sh dev

  ACTION=diagnose ./scripts/activate.sh dev

Description:
  1. Prepare Git state.
  2. Validate the environment.
  3. Encrypt secrets.
  4. Validate GitOps configuration.
  5. Optionally validate KUBAPP applications.
  6. Ask for push confirmation unless PUSH=true or yes.
  7. Finalize Git operations.

EOF
}

