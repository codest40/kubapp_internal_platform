#!/bin/bash

set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

require_binary "jq"

MODULE_NAME="filesystem_drift"

evid_dir="${EVIDENCE_DIR}"

current="$evid_dir/filesystem.json"
previous="$evid_dir/filesystem_older.json"
drift_file="$(evidence_file "filesystem_drift")"

all_files=("$current" "$previous")

log_info "Starting Filesystem drift check......"

for each in "${all_files[@]}"; do
    if [[ ! -f "$each" || ! -s "$each" ]]; then
        STATUS="fail"
        ERRORS+=("filesystem evidence file missing or empty: $each")

        log_info "Unable to check filesystem drift."
        log_info "Invalid or empty file: $each"
        return 1
    fi
done


# ============================================================
# COLLECT DRIFT
# ============================================================

drift_data="$(
    jq -n \
        --slurpfile old "$previous" \
        --slurpfile current "$current" '

        ($old[0].files // {}) as $old_files |
        ($current[0].files // {}) as $current_files |

        {
            modified: (
                reduce ($old_files | keys[]) as $key
                    ( {};

                        if $current_files[$key] != null then

                            if (
                                $old_files[$key].size != $current_files[$key].size
                                or
                                $old_files[$key].permissions != $current_files[$key].permissions
                                or
                                $old_files[$key].uid != $current_files[$key].uid
                                or
                                $old_files[$key].gid != $current_files[$key].gid
                                or
                                $old_files[$key].modified != $current_files[$key].modified
                                or
                                $old_files[$key].changed != $current_files[$key].changed
                            ) then

                                .[$key] = {
                                    previous: $old_files[$key],
                                    current: $current_files[$key]
                                }

                            else
                                .
                            end

                        else
                            .
                        end
                    )
            ),

            removed: (
                reduce ($old_files | keys[]) as $key
                    ( {};

                        if $current_files[$key] == null then
                            .[$key] = $old_files[$key]
                        else
                            .
                        end
                    )
            )
        }
    '
)"


# ============================================================
# SUMMARY
# ============================================================

modified_count="$(
    jq '.modified | length' <<< "$drift_data"
)"

removed_count="$(
    jq '.removed | length' <<< "$drift_data"
)"


# ============================================================
# WRITE EVIDENCE
# ============================================================

jq -n \
    --arg module "$MODULE_NAME" \
    --arg script "$SCRIPT_NAME" \
    --arg timestamp "$TIMESTAMP" \
    --arg status "$STATUS" \
    --argjson modified "$modified_count" \
    --argjson removed "$removed_count" \
    --argjson drift "$drift_data" \
    '{
        module: $module,
        script: $script,
        timestamp: $timestamp,
        status: $status,

        summary: {
            modified: $modified,
            removed: $removed
        },

        modified: $drift.modified,
        removed: $drift.removed
    }' > "$drift_file"


# ============================================================
# OUTPUT
# ============================================================

if [[ -s "$drift_file" ]]; then
    log_info "Successfully Created Filesystem drift report: $drift_file"
fi
