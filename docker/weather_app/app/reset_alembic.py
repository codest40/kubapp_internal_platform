#!/usr/bin/env python3
"""
Reset Alembic migrations safely using psycopg2 (Postgres only).
SQLite fallback is ignored.
"""

import os
import sys
import psycopg2
from urllib.parse import urlparse

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    print("[FATAL] DATABASE_URL is not set. Aborting.")
    sys.exit(1)

if DATABASE_URL.startswith("sqlite"):
    print("[FATAL] Refusing to reset Alembic on SQLite.")
    print("[INFO] SQLite is fallback-only and must never be reset this way.")
    sys.exit(1)

if not DATABASE_URL.startswith("postgresql://"):
    print("[FATAL] Unsupported DATABASE_URL scheme.")
    sys.exit(1)

print("[ALEMBIC] Using PostgreSQL database")
parsed_url = urlparse(DATABASE_URL)
print(f"[ALEMBIC] URL host: {parsed_url.hostname}")

# Connect and drop/recreate public schema
try:
    with psycopg2.connect(DATABASE_URL) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            print("[ALEMBIC] Dropping and recreating public schema...")
            cur.execute("DROP SCHEMA IF EXISTS public CASCADE;")
            cur.execute("CREATE SCHEMA public;")
            cur.execute("GRANT ALL ON SCHEMA public TO public;")
    print("[ALEMBIC] Public schema reset successfully ✅")
except psycopg2.Error as e:
    print(f"[FATAL] Could not reset schema: {e}")
    sys.exit(1)

# Clear Alembic versions
versions_dir = "/app/alembic/versions"
if os.path.isdir(versions_dir):
    print("[ALEMBIC] Clearing alembic/versions directory...")
    for f in os.listdir(versions_dir):
        os.remove(os.path.join(versions_dir, f))
else:
    print("[WARN] /app/alembic/versions not found")

print("[ALEMBIC] Alembic reset completed successfully ✅")
