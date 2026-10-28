#!/usr/bin/env python3
"""
Wait for DB before app start.
Modes:
- sqlite_only: use SQLite, skip Postgres
- postgres_only: use Postgres only
- try_postgres: try Postgres first, fallback to SQLite
"""

import os
import subprocess
from wait_for_db_core import wait_for_database
from local_tz import timer

FINAL_DB_MODE = os.getenv("FINAL_DB_MODE")
DATABASE_URL = os.getenv("DATABASE_URL")
SQLITE_FALLBACK = os.getenv("DATABASE_URL_SQLITE", "sqlite:////tmp/edgepaas/fallback.db")
MAX_RETRIES = int(os.getenv("MAX_RETRIES", 6))
RETRY_INTERVAL = int(os.getenv("RETRY_INTERVAL", 3))

def is_postgres(url: str) -> bool:
    return url and url.startswith("postgresql://")

def is_sqlite(url: str) -> bool:
    return url and url.startswith("sqlite")

def add_sslmode(url: str) -> str:
    """Ensure sslmode=require for Postgres"""
    from urllib.parse import urlparse, parse_qs, urlencode, urlunparse
    if not is_postgres(url):
        return url
    parsed = urlparse(url)
    query = parse_qs(parsed.query)
    query["sslmode"] = ["require"]
    new_query = urlencode(query, doseq=True)
    return urlunparse(parsed._replace(query=new_query))

print(f"[{timer()}] [WAIT] DB mode: {FINAL_DB_MODE}")

final_db_url = None

if FINAL_DB_MODE == "sqlite_only":
    final_db_url = SQLITE_FALLBACK
    run_migrations = "false"
    print(f"[{timer()}] [DB] Using SQLite only: {final_db_url}")

elif FINAL_DB_MODE == "postgres_only":
    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL must be set for Postgres mode")
    try:
        wait_for_database(add_sslmode(DATABASE_URL), MAX_RETRIES, RETRY_INTERVAL)
        final_db_url = DATABASE_URL
        run_migrations = "true"
        print(f"[{timer()}] [DB] Connected to PostgreSQL: {final_db_url}")
    except RuntimeError as e:
        raise RuntimeError(f"[{timer()}] PostgreSQL unreachable: {e}")

elif FINAL_DB_MODE == "try_postgres":
    try:
        wait_for_database(add_sslmode(DATABASE_URL), MAX_RETRIES, RETRY_INTERVAL)
        final_db_url = DATABASE_URL
        run_migrations = "true"
        print(f"[{timer()}] [DB] Connected to PostgreSQL: {final_db_url}")
    except RuntimeError:
        final_db_url = SQLITE_FALLBACK
        run_migrations = "false"
        print(f"[{timer()}] [WARN] PostgreSQL unreachable. Falling back to SQLite: {final_db_url}")

else:
    raise RuntimeError(f"Unknown FINAL_DB_MODE={FINAL_DB_MODE}")

# Export final for subsequent scripts
os.environ["DATABASE_URL"] = final_db_url

# validate just to be sure
run_migrations = "true" if final_db_url.startswith("postgresql://") else "false"
final_db_mode = "sqlite_only" if run_migrations == "false" else FINAL_DB_MODE

# Write the export file
try:
    with open("/tmp/db_env.sh", "w") as f:
        f.write(f"export DATABASE_URL='{final_db_url}'\n")
        f.write(f"export RUN_MIGRATIONS='{run_migrations}'\n")
        f.write(f"export FINAL_DB_MODE='{final_db_mode}'\n")
except Exception as e:
    print(f"[ERROR] ❌ Failed to write /tmp/db_env.sh: {e}")
    raise
print("[WAIT] Wrote /tmp/db_env.sh successfully")

print(f"[{timer()}] [DONE] Database ready: {final_db_url}")
