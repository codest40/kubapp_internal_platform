#!/bin/bash
set -euo pipefail

local_env="${ENV:-prod}"
local_env="${local_env,,}"

TZ="Africa/Lagos"
export TZ

timer() { date +"%Y:%m:%d_%H:%M:%S"; }
echo "[ENTRY] $(timer) Bootstrapping environment..."
source ./bootstrap_env.sh

echo "[ENTRY] $(timer) Waiting for DB..."
python wait_for_db.py

# ----------------------------
# Source db_env file if exists
# ----------------------------
if [[ -f /tmp/db_env.sh ]]; then
    echo "[ENTRY] Checking /tmp/db_env.sh ..."
    source /tmp/db_env.sh
    echo "[ENTRY] DATABASE_URL=$DATABASE_URL"
    echo "[ENTRY] RUN_MIGRATIONS=$RUN_MIGRATIONS"
    echo "[ENTRY] FINAL_DB_MODE=$FINAL_DB_MODE"
else
    echo "[ENTRY] Sourcing /tmp DB ENV file FAILED ❌"
fi

# ----------------------------
# Create fallback SQLite DB if SQLite is enabled
# ----------------------------
if [[ "$FINAL_DB_MODE" == "sqlite_only" ]]; then
    echo "[ENTRY] SQLite confirmed by runtime resolver"
    mkdir -p /tmp/edgepaas
    chmod 755 /tmp/edgepaas

    if [ ! -f /tmp/edgepaas/fallback.db ]; then
        touch /tmp/edgepaas/fallback.db
        chmod 644 /tmp/edgepaas/fallback.db
        echo "[ENTRY] Created fallback.db ✅"
    else
        echo "[ENTRY] /tmp/edgepaas/fallback.db already exists"
    fi
    python create_sqlite_tables.py
fi

# ----------------------------
# Run Alembic migrations if Postgres is active
# ----------------------------
if [[ "${RUN_MIGRATIONS,,}" == "true" ]]; then
    echo "[ALEMBIC] Running migrations..."
    if ! python -m alembic upgrade head; then
        echo "[ALEMBIC] Migration failed. Resetting..."
        python reset_alembic.py
        echo "[ALEMBIC] Retrying migrations..."
        python -m alembic upgrade head
    fi
else
    echo "[ALEMBIC] Skipping migrations (SQLite or RUN_MIGRATIONS=false)"
fi

# ----------------------------
# Decide Port
# ----------------------------
PORT="${CONTAINER_PORT:-8080}"
if [[ "$local_env" == "dev" ]]; then
    PORT="${CONTAINER_PORT:-8090}"
fi

# Run SRE startup checks
python sre/verify_startup.py

# ----------------------------
# Final summary
# ----------------------------
echo "=============================================="
echo "[SUMMARY] Environment Ready"
echo "  ENVIRONMENT       : $local_env"
echo "  FINAL_DB_MODE     : ${FINAL_DB_MODE:-unknown}"
echo "  DATABASE_URL      : ${DATABASE_URL:-unknown}"
echo "  RUN_MIGRATIONS    : ${RUN_MIGRATIONS:-true}"
echo "  FASTAPI_PORT      : $PORT"
echo "=============================================="

# ----------------------------
# Start FastAPI
# ----------------------------
echo "[START] Starting FastAPI on port $PORT..."
exec uvicorn main:app --host 0.0.0.0 --port "$PORT"
