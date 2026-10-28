# app/sre/verify_startup.py

import os
import sys
import time

from sqlalchemy import create_engine, text
from alembic.config import Config
from alembic.script import ScriptDirectory
from alembic.runtime.migration import MigrationContext

# allow importing logger and send_alert from the same folder
sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from logger import logger
from send_alert import send_alert

DATABASE_URL = os.environ.get("DATABASE_URL")
FINAL_DB_MODE = os.environ.get("FINAL_DB_MODE")

if not DATABASE_URL or not FINAL_DB_MODE:
    print("[VERIFY STARTUP] Env Variables NOT fully detected")

def check_db():
    """Check database connectivity"""
    start = time.time()
    try:
        engine = create_engine(DATABASE_URL)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        logger.info(f"✅ DB connectivity OK ({time.time() - start:.2f}s)")
    except Exception as e:
        if FINAL_DB_MODE == "sqlite_only":
            logger.warning(f"[Verify] ⚠️  Using DB SQLite fallback: {e}")
            send_alert(f"DB connection failed but SQLite fallback active: {e}", use_fallback_db=True)
        else:
            raise


def check_migrations():
    """Check Alembic migrations"""
    # Skip migrations check if using SQLite fallback
    if FINAL_DB_MODE in ("sqlite_only", "try_postgres"):
        if DATABASE_URL.startswith("sqlite"):
            logger.info("ℹ️ Skipping Alembic migration check for SQLite fallback")
            return

    start = time.time()
    alembic_cfg = Config("alembic.ini")
    script = ScriptDirectory.from_config(alembic_cfg)

    engine = create_engine(DATABASE_URL)
    with engine.connect() as conn:
        context = MigrationContext.configure(conn)
        current_rev = context.get_current_revision()
        head_rev = script.get_current_head()

    if current_rev != head_rev:
        raise RuntimeError(f"Alembic mismatch: current={current_rev}, head={head_rev}")

    logger.info(f"✅ Alembic migrations OK ({time.time() - start:.2f}s)")


def run_startup_checks():
    """Run all startup checks"""
    check_db()
    check_migrations()


def main():
    try:
        run_startup_checks()
        logger.info("✅ Startup verification PASSED")
    except Exception as e:
        logger.error("❌ Startup verification FAILED")
        # Only send alert if not using SQLite fallback
        use_fallback = FINAL_DB_MODE == "sqlite_only"
        send_alert(f"Startup verification failed: {e}", use_fallback_db=use_fallback)
        sys.exit(1)


if __name__ == "__main__":
    main()
