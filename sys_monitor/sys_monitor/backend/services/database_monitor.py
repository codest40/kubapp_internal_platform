import asyncio
import time
from datetime import datetime, timezone

import psycopg
from psycopg import OperationalError

from config import settings


def check_database_connection() -> dict:
    """Test PostgreSQL connectivity and measure query response time."""

    checked_at = datetime.now(timezone.utc).isoformat()

    if not all(
        [
            settings.db_host,
            settings.db_name,
            settings.db_user,
            settings.db_password,
        ]
    ):
        return {
            "name": "postgresql_connection",
            "status": "unknown",
            "checked_at": checked_at,
            "duration_ms": None,
            "message": "Database connection configuration is incomplete",
        }

    started = time.perf_counter()

    try:
        with psycopg.connect(
            host=settings.db_host,
            port=settings.db_port,
            dbname=settings.db_name,
            user=settings.db_user,
            password=settings.db_password.get_secret_value(),
            connect_timeout=settings.db_connect_timeout,
            sslmode=settings.db_sslmode,
        ) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                result = cursor.fetchone()

        duration_ms = round(
            (time.perf_counter() - started) * 1000,
            2,
        )

        if result != (1,):
            return {
                "name": "postgresql_connection",
                "status": "unhealthy",
                "checked_at": checked_at,
                "duration_ms": duration_ms,
                "message": "Health-check query returned an unexpected result",
            }

        return {
            "name": "postgresql_connection",
            "status": "healthy",
            "checked_at": checked_at,
            "duration_ms": duration_ms,
            "message": "Connection successful; SELECT 1 completed",
        }

    except (psycopg.Error, OSError, TimeoutError) as exc:
        duration_ms = round(
            (time.perf_counter() - started) * 1000,
            2,
        )

        if isinstance(exc, OperationalError):
            message = "Database connection failed"
        else:
            message = f"Database health check failed: {type(exc).__name__}"

        return {
            "name": "postgresql_connection",
            "status": "unhealthy",
            "checked_at": checked_at,
            "duration_ms": duration_ms,
            "message": message,
        }


async def get_database_status() -> dict:
    """Run the blocking database check without blocking the event loop."""

    result = await asyncio.to_thread(check_database_connection)

    return {
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "id": "kubapp-postgresql",
        "name": "KUBAPP PostgreSQL",
        "engine": "postgres",
        "provider": "aws",
        "status": result["status"],
        "checks": [result],
    }
