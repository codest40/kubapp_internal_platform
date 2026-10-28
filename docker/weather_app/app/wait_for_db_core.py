#!/usr/bin/env python3
"""
Core DB wait logic.
PostgreSQL ONLY.
"""

import time
import psycopg2
from local_tz import timer

def wait_for_database(db_url: str, max_retries: int = 5, retry_interval: int = 3) -> None:
    start = time.time()

    for attempt in range(1, max_retries + 1):
        now_str = timer()
        print(f"[WAIT_FOR_DB_CORE: {now_str}] Attempt {attempt}/{max_retries}")
        try:
            conn = psycopg2.connect(db_url)
            conn.close()
            elapsed = time.time() - start
            print(f"[WAIT_FOR_DB_CORE] Database ready after {elapsed:.2f}s")
            return
        except psycopg2.OperationalError as e:
            print(f"[WAIT_FOR_DB_CORE] DB not ready: {e}")
            if attempt < max_retries:
                time.sleep(retry_interval)
            else:
                elapsed = time.time() - start
                raise RuntimeError(
                    f"PostgreSQL unreachable after {max_retries} retries ({elapsed:.2f}s)"
                )
