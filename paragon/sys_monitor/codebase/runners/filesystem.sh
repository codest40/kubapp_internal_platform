#!/bin/bash

set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

require_binary "jq"

evid_dir="${EVIDENCE_DIR}"
inv_file="$evid_dir/inventory.json"
fs_file="$(evidence_file "filesystem")"

if [[ ! -f "$inv_file" ]]; then
    echo "Inventory File is NOT available, exiting..."
    exit 1
fi

extract() {
    local file="$1"
    local mod
    local status
    local f
    local p
    local pp
    local s

    local -a scripts=()
    local -a ss=()
    local -a all_files=()

    mod=$(jq -r '.module' "$file")
    status=$(jq -r '.status' "$file")

    mapfile -t all_files < <(
          jq -r '.files.all_files[]' "$file"
    )

    if [[ "${mod,,}" != "discovery" || "${status,,}" != "pass" ]]; then
      echo "stale or expired data in $file"
      exit 1
    fi

    for each in "${all_files[@]}"; do
          if [[ "$each" != *docker/* ]]; then
              scripts+=("$each")
          fi
    done

    f="%n|%s|%i|%a|%u|%g|%x|%y|%z|%w"
    p="$PROJECT_ROOT"
    for each in "${scripts[@]}"; do
        pp="$p/$each"

        if [[ -f "$pp" ]]; then
            if s=$(stat -c "$f" "$pp" 2>/dev/null); then
              ss+=("$s")
            else
              :
            fi
        fi
    done

    IFS='.' read fil gil <<<"$fs_file"
    older="${fil}_older.${gil}"
    cp "$fs_file" "$older"
    store=()
    filesystem_data="$(
      for one in "${ss[@]}"; do
        IFS='|' read -r \
            filename \
            size \
            inode \
            permissions \
            uid \
            gid \
            access \
            modify \
            change \
            birth <<< "$one"
        filename="$(relative_path "$filename")"
        jq -n \
            --arg filename "$filename" \
            --arg size "$size" \
            --arg inode "$inode" \
            --arg permissions "$permissions" \
            --arg uid "$uid" \
            --arg gid "$gid" \
            --arg access "$access" \
            --arg modify "$modify" \
            --arg change "$change" \
            --arg birth "$birth" \
            '{
                ($filename): {
                  size: $size,
                  inode: $inode,
                  permissions: $permissions,
                  uid: $uid,
                  gid: $gid,
                  access: $access,
                  modified: $modify,
                  changed: $change,
                  birth: $birth
                }
            }'
      done | jq -s 'add // {}'
    )"
    jq -n \
          --arg module "filesystem" \
          --arg script "$SCRIPT_NAME" \
          --arg timestamp "$TIMESTAMP" \
          --arg status "$STATUS" \
          --argjson total_checked "${#ss[@]}" \
          --argjson files "$filesystem_data" \
          '{
              module: $module,
              script: $script,
              timestamp: $timestamp,
              status: $status,

              summary: {
                  total_checked: $total_checked
              },

              files: $files
          }' > "$fs_file"

    if [[ -f "$fs_file" && -s "$fs_file" ]]; then
        log_info "Filesystem file created: $fs_file"
    fi
}

start() {
    local file="$1"

    extract "$file"
}

log_info "Starting Filesystem Check..."
start "$inv_file"
log_info  "Done!"
