#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"

EVIDENCE_DIR="${EVIDENCE_DIR}"
OUTPUT_FILE="${EVIDENCE_DIR}/metrics.prom"

> "$OUTPUT_FILE"

log_info "metrics engine starting"

emit() {
    echo "$1" >> "$OUTPUT_FILE"
}

status_to_value() {
    case "$1" in
        pass|completed|success)
            echo 1
            ;;
        *)
            echo 0
            ;;
    esac
}

# ============================================================
# PLATFORM METADATA
# ============================================================

emit "kubapp_last_scan_timestamp $(date +%s)"
emit "kubapp_scan_success 1"

platform_health_total=0
platform_health_count=0

# ============================================================
# PROCESS EVIDENCE FILES
# ============================================================

for file in "${EVIDENCE_DIR}"/*.json; do
    [[ ! -f "$file" ]] && continue

    filename="$(basename "$file")"
    # Historical filesystem snapshot.
    # Used only by filesystem_drift.sh.
    [[ "$filename" == *older* ]] && continue

    module=$(jq -r '.module // "unknown"' "$file" | tr '[:upper:]' '[:lower:]')

    status=$(jq -r '.status // "unknown"' "$file")
    status_value=$(status_to_value "$status")

    total_checked=$(jq -r '.summary.total_checked // 0' "$file")

    findings_total=$(jq -r '.findings // [] | length' "$file")

    critical=$(jq -r '.summary.critical // 0' "$file")
    warnings=$(jq -r '.summary.warnings // 0' "$file")
    errors=$(jq -r '.summary.errors // 0' "$file")

    # ========================================================
    # MODULE STATUS
    # ========================================================

    emit "kubapp_module_status{module=\"${module}\"} ${status_value}"

    emit "kubapp_total_checked{module=\"${module}\"} ${total_checked}"

    emit "kubapp_findings_total{module=\"${module}\"} ${findings_total}"

    emit "kubapp_critical_total{module=\"${module}\"} ${critical}"
    emit "kubapp_warning_total{module=\"${module}\"} ${warnings}"
    emit "kubapp_error_total{module=\"${module}\"} ${errors}"

    # ========================================================
    # FINDING TYPES
    # ========================================================

    jq -r '
        .findings // []
        | group_by(.type)
        | map({
            type: .[0].type,
            count: length
          })
        | .[]
        | "kubapp_finding_type_total{type=\"" +
          (.type|tostring) +
          "\"} " +
          (.count|tostring)
    ' "$file" >> "$OUTPUT_FILE"


    # ========================================================
    # FILESYSTEM EVIDENCE
    # ========================================================

    if [[ "$filename" == "filesystem.json" || "$module" == "filesystem" ]]; then
        filesystem_total=$(
            jq '.files // {} | length' "$file"
        )

        emit \
            "kubapp_filesystem_total ${filesystem_total}"
    fi

    # ========================================================
    # FILESYSTEM DRIFT EVIDENCE
    # ========================================================
    if [[ "$filename" == "filesystem_drift.json" ]]; then
        filesystem_modified=$(
            jq '.modified // {} | length' "$file"
        )

        filesystem_removed=$(
            jq '.removed // {} | length' "$file"
        )

        emit \
            "kubapp_filesystem_drift_modified ${filesystem_modified}"

        emit \
            "kubapp_filesystem_drift_removed ${filesystem_removed}"

        filesystem_size_changed=$(
            jq '
                [
                    .modified[]?
                    | select(
                        .previous.size != .current.size
                    )
                ]
                | length
            ' "$file"
            )

        filesystem_permissions_changed=$(
            jq '
                [
                    .modified[]?
                    | select(
                        .previous.permissions != .current.permissions
                    )
                ]
                | length
            ' "$file"
        )

        filesystem_uid_changed=$(
            jq '
                [
                    .modified[]?
                    | select(
                        .previous.uid != .current.uid
                    )
                ]
                | length
            ' "$file"
        )

        filesystem_gid_changed=$(
            jq '
                [
                    .modified[]?
                    | select(
                        .previous.gid != .current.gid
                    )
                ]
                | length
            ' "$file"
        )

        filesystem_access_changed=$(
            jq '
                [
                    .modified[]?
                    | select(
                        .previous.access != .current.access
                    )
                ]
                | length
            ' "$file"
        )

        filesystem_modified_changed=$(
            jq '
                [
                    .modified[]?
                    | select(
                        .previous.modified != .current.modified
                    )
                ]
                | length
            ' "$file"
        )

        filesystem_changed_changed=$(
            jq '
                [
                    .modified[]?
                    | select(
                        .previous.changed != .current.changed
                    )
                ]
                | length
            ' "$file"
        )

        emit \
            "kubapp_filesystem_size_changed ${filesystem_size_changed}"

        emit \
            "kubapp_filesystem_permissions_changed ${filesystem_permissions_changed}"

        emit \
            "kubapp_filesystem_uid_changed ${filesystem_uid_changed}"

        emit \
            "kubapp_filesystem_gid_changed ${filesystem_gid_changed}"

        emit \
            "kubapp_filesystem_access_changed ${filesystem_access_changed}"

        emit \
            "kubapp_filesystem_mtime_changed ${filesystem_modified_changed}"

        emit \
            "kubapp_filesystem_ctime_changed ${filesystem_changed_changed}"
    fi

    # ========================================================
    # MODULE HEALTH SCORE
    # ========================================================

    case "$module" in

        drift)
            score=100
            ;;

        filesystem)
            score=100
            ;;

        filesystem_drift)
            score=100
            ;;

        architecture)
            score=$(jq -r '.summary.architecture_score // 100' "$file")
            ;;

        security)
            score=$((100 - critical*10 - warnings*2))
            ;;

        validation)
            score=$((100 - warnings))
            ;;

        discovery)
            score=100
            ;;

        *)
            score=100
            ;;
    esac

    (( score < 0 )) && score=0
    (( score > 100 )) && score=100

    emit "kubapp_module_score{module=\"${module}\"} ${score}"

    # ========================================================
    # PLATFORM HEALTH INPUTS
    # ========================================================

    case "$module" in
        discovery)
            ;;
        *)
            platform_health_total=$((platform_health_total + score))
            platform_health_count=$((platform_health_count + 1))
            ;;
    esac

done

# ============================================================
# INVENTORY METRICS
# ============================================================

inventory_file="${EVIDENCE_DIR}/inventory.json"

if [[ -f "$inventory_file" ]]; then

  emit "kubapp_total_files $(jq -r '.statistics.all_files_count // 0' "$inventory_file")"

  emit "kubapp_total_workflows $(jq -r '.statistics.workflow_count // 0' "$inventory_file")"

  emit "kubapp_total_shell_scripts $(jq -r '.statistics.shell_script_count // 0' "$inventory_file")"

  emit "kubapp_total_terraform_roots $(jq -r '.statistics.terraform_root_count // 0' "$inventory_file")"

  emit "kubapp_total_terraform_modules $(jq -r '.statistics.terraform_module_count // 0' "$inventory_file")"

  emit "kubapp_total_dockerfiles $(jq -r '.statistics.dockerfile_count // 0' "$inventory_file")"

  emit "kubapp_total_k8s_manifests $(jq -r '.statistics.k8s_manifest_count // 0' "$inventory_file")"

fi

# ============================================================
# PLATFORM HEALTH
# ============================================================

if (( platform_health_count > 0 )); then
    platform_health=$((platform_health_total / platform_health_count))
else
    platform_health=100
fi

emit "kubapp_platform_health ${platform_health}"

log_info "metrics written to ${OUTPUT_FILE}"
