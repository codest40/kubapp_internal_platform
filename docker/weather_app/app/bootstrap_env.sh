#!/bin/bash
set -euo pipefail

echo "[BOOTSTRAP] Initializing environment..."

# ----------------------------
# Default raw values
# ----------------------------
USE_SQLITE="${USE_SQLITE:-true}"
BOTH_DB="${BOTH_DB:-true}"
RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"

DATABASE_URL_SQLITE="${DATABASE_URL_SQLITE:-sqlite:////tmp/edgepaas/fallback.db}"

# ----------------------------
# Normalize booleans: strip spaces/quotes and lowercase
# ----------------------------
for var_name in USE_SQLITE BOTH_DB RUN_MIGRATIONS; do
    raw_val="${!var_name}"
    cleaned_val="$(echo "$raw_val" | tr -d '[:space:]\"' | tr '[:upper:]' '[:lower:]')"

    # Validate and fallback if invalid
    if [[ "$cleaned_val" != "true" && "$cleaned_val" != "false" ]]; then
        echo "❌ Invalid boolean: $var_name=$raw_val (after cleaning: $cleaned_val). Using default."
        case "$var_name" in
            USE_SQLITE|BOTH_DB)
                cleaned_val="false"
                ;;
            RUN_MIGRATIONS)
                cleaned_val="true"
                ;;
        esac
    fi

    # Export cleaned/fallback value
    export "$var_name"="$cleaned_val"
    echo "[INFO] $var_name set to '$cleaned_val'"
done

# ----------------------------
# Resolve DB mode
# ----------------------------
if [[ "$USE_SQLITE" == "true" ]]; then
    export FINAL_DB_MODE="sqlite_only"
    export DATABASE_URL="$DATABASE_URL_SQLITE"
    export RUN_MIGRATIONS="false"
    echo "[BOOTSTRAP] SQLite-only mode enabled"

elif [[ "$BOTH_DB" == "true" ]]; then
    export FINAL_DB_MODE="try_postgres"
    export RUN_MIGRATIONS="true"
    echo "[BOOTSTRAP] BOTH_DB mode enabled: Try Postgres first, fallback to SQLite"

else
    export FINAL_DB_MODE="postgres_only"
    export RUN_MIGRATIONS="true"
    if [[ -z "${DATABASE_URL:-}" ]]; then
        echo "❌ DATABASE_URL must be set for Postgres mode"
        exit 1
    fi
    echo "[BOOTSTRAP] Postgres-only mode enabled"
fi

export EMAIL_TO="${EMAIL_TO:-None}"
export EMAIL_FROM="${EMAIL_FROM:-None}"
export EMAIL_PASS="${EMAIL_PASS:-None}"
export OPENWEATHER_API_KEY="${OPENWEATHER_API_KEY:-None}"

# ----------------------------
# Final report
# ----------------------------
echo "[BOOTSTRAP] Environment configuration:"
echo "  FINAL_DB_MODE=$FINAL_DB_MODE"
echo "  USE_SQLITE=$USE_SQLITE"
echo "  BOTH_DB=$BOTH_DB"
echo "  RUN_MIGRATIONS=$RUN_MIGRATIONS"
echo "  DATABASE_URL=$DATABASE_URL"
echo "[BOOTSTRAP] Done. ✅"
