# create_sqlite_tables.py
import os
from sqlalchemy import create_engine
from models import Base

DATABASE_URL = os.environ.get("DATABASE_URL")

if not DATABASE_URL or not DATABASE_URL.startswith("sqlite"):
    print("[INFO] Not using SQLite, skipping table creation")
    exit(0)

print("[INFO] Creating tables for SQLite...")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False}
)

Base.metadata.create_all(bind=engine)

print("[INFO] SQLite tables created ✅")
