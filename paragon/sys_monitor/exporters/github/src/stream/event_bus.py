import sqlite3
import json
import os
from pathlib import Path

# ============================================================
# SOURCE OF TRUTH: SQLITE EVENT STORE
# ============================================================

DB_PATH = Path(os.getenv("EVENT_DB_PATH", "/data/github_events.db"))

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            repo TEXT NOT NULL,
            payload TEXT NOT NULL,
            timestamp REAL NOT NULL
        )
    """)

    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_timestamp ON events(timestamp)
    """)
    return conn


# ------------------------------------------------------------
# PUBLISH EVENT (APPEND-ONLY TRUTH)
# ------------------------------------------------------------
def publish(event):
    conn = get_conn()

    conn.execute(
        """
        INSERT INTO events (event_type, repo, payload, timestamp)
        VALUES (?, ?, ?, ?)
        """,
        (
            event.event_type,
            event.repo,
            json.dumps(event.payload),
            event.timestamp.timestamp(),
        ),
    )

    conn.commit()
    conn.close()


# ------------------------------------------------------------
# CONSUME EVENTS (REPLAY MODEL)
# ------------------------------------------------------------
def consume_all():
    conn = get_conn()

    cursor = conn.execute(
        """
        SELECT event_type, repo, payload, timestamp FROM events
        ORDER BY id ASC
        """
    )

    rows = cursor.fetchall()

    # Clear table after consumption (simple worker model)
    conn.execute("DELETE FROM events")
    conn.commit()
    conn.close()

    events = []

    for event_type, repo, payload, timestamp in rows:
        events.append({
            "event_type": event_type,
            "repo": repo,
            "payload": json.loads(payload),
            "timestamp": timestamp
        })

    return events

def query_events_since(since_ts: float):
    """
    Returns events from SQLite within a time window.
    """
    conn = get_conn()

    cursor = conn.execute(
        """
        SELECT event_type, repo, payload, timestamp
        FROM events
        WHERE timestamp >= ?
        ORDER BY timestamp ASC
        """,
        (since_ts,),
    )

    rows = cursor.fetchall()
    conn.close()

    import json

    events = []

    for event_type, repo, payload, timestamp in rows:
        events.append({
            "event_type": event_type,
            "repo": repo,
            "payload": json.loads(payload),
            "timestamp": timestamp
        })

    return events

