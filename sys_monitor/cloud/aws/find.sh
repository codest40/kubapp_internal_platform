#!/usr/bin/env bash
# find.sh - Multi-extension file explorer

set -euo pipefail

# -------------------------------
# Colors
# -------------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
NC="\033[0m"

# -------------------------------
# FUNCTIONS
# -------------------------------

usage() {
  echo "Usage:"
  echo "  ./find.sh <ext1> <ext2> ... <action>"
  echo
  echo "Examples:"
  echo "  ./find.sh sh yml py cat"
  echo "  ./find.sh tf tfvars list"
  echo
  echo "Actions:"
  echo "  list  -> list files only"
  echo "  cat   -> print file contents"
  exit 1
}

run_search() {
  if [[ "$#" -lt 2 ]]; then
    usage
  fi

  # Last argument = action
  action="${@: -1}"

  # All others = extensions
  exts=("${@:1:$#-1}")

  # Build find expression
  find_expr=()
  for ext in "${exts[@]}"; do
    find_expr+=( -name "*.${ext}" -o )
  done
  unset 'find_expr[-1]'  # remove last -o

  echo -e "${CYAN}🔹 Extensions: ${exts[*]} | Mode: $action${NC}"

  mapfile -t files < <(find . -type f \( "${find_expr[@]}" \) | sort)

  if [[ ${#files[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No matching files found.${NC}"
    exit 0
  fi

  for f in "${files[@]}"; do
    if [[ "$action" == "list" ]]; then
      echo -e "${YELLOW}$f${NC}"
    elif [[ "$action" == "cat" ]]; then
      echo -e "${YELLOW}==================== $f ====================${NC}"
      cat "$f"
      echo
    else
      echo -e "${RED}❌ Unknown action: $action${NC}"
      usage
    fi
  done
}

# -------------------------------
# INTERACTIVE MODE (fallback)
# -------------------------------
interactive_mode() {
  echo -e "${CYAN}No arguments provided. Entering interactive mode...${NC}"
  echo
  read -rp "Enter extensions (space separated, e.g. 'tf tfvars'): " ext_input
  read -rp "Action (list/cat): " action

  # Convert input string to array
  read -ra ext_array <<< "$ext_input"

  run_search "${ext_array[@]}" "$action"
}

# -------------------------------
# MAIN
# -------------------------------

if [[ "$#" -gt 0 ]]; then
  run_search "$@"
else
  interactive_mode
fi
