import os
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv

load_dotenv()

try:
    DATABASE_URL = os.environ["DATABASE_URL"]
    if DATABASE_URL:
      print(f"[INFO(From DB Engine Script)]: Detected DB ✅")
except KeyError:
    raise RuntimeError("DATABASE_URL not set in environment!")


# Detect if using SQLite
is_sqlite = DATABASE_URL.startswith("sqlite")

if is_sqlite:
    # SQLite engine options
    engine = create_engine(
        DATABASE_URL,
        connect_args={"check_same_thread": False},  # Required for FastAPI async
        echo=False
    )

    # Ensure foreign keys are enforced
    @event.listens_for(engine, "connect")
    def _enable_foreign_keys(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON;")
        cursor.close()

    print(f"[INFO(From DB Engine Script)]: Using SQLite, foreign keys enabled ✅")

else:
    # Standard Postgres / other DBs
    engine = create_engine(DATABASE_URL)
    print(f"[INFO(From DB Engine Script)]: Using {DATABASE_URL.split(':')[0]} ✅")

# Session setup
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Dependency for FastAPI
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

