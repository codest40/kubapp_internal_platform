# app/sre/health.py
import os
import sys
from fastapi import APIRouter, status
from fastapi.responses import JSONResponse

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from logger import logger
from verify_startup import check_db, check_migrations


router = APIRouter()

DATABASE_URL = os.environ.get("DATABASE_URL")
FINAL_DB_MODE = os.environ.get("FINAL_DB_MODE")

@router.get("/health/live")
def liveness():
    """
    Liveness probe.
    Confirms the app process is running.
    No dependency checks.
    """
    logger.info("Liveness check OK ✅")
    return JSONResponse(
        status_code=status.HTTP_200_OK,
        content={
            "status": "alive",
            "icon": "✅",
            "message": "App process is running"
        }
    )


@router.get("/health/ready")
def readiness():
    """
    Readiness probe.
    Confirms the app is ready to receive traffic.
    Checks:
      - DB connectivity
      - Alembic migration state (skipped for SQLite)
    """
    try:
        check_db()

        # Only run migrations check if using Postgres
        if not DATABASE_URL.startswith("sqlite"):
            check_migrations()
        else:
            logger.info("Readiness migrations check skipped (SQLite fallback) ✅")

        logger.info("Readiness check OK ✅")
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "status": "ready",
                "icon": "✅",
                "message": "Database and migrations are healthy"
            }
        )

    except Exception as exc:
        logger.error(f"Readiness check FAILED ❌: {exc}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "not ready",
                "icon": "❌",
                "message": str(exc)
            }
        )
