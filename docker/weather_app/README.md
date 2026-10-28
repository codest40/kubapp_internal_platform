# ============================================================
#  EDGEPAAS — DOCKER LAYER
# ============================================================

# ------------------------------------------------------------
#  PURPOSE
# ------------------------------------------------------------
- This directory contains everything required to run the EdgePaaS application inside Docker containers.
- The Docker layer is responsible for runtime orchestration and safety.
- It does NOT provision infrastructure.
- It does NOT contain infrastructure automation logic.
- It does NOT manage CI/CD pipelines.
- It provides a predictable, environment-agnostic execution unit.

In short:

Terraform builds the world → Ansible prepares the host → Docker runs the app

# ------------------------------------------------------------
#  RESPONSIBILITIES
# ------------------------------------------------------------
Docker handles:

- Packaging the application and all dependencies
- Normalizing runtime behavior across environments
- Handling startup sequencing and database readiness
- Bootstrapping schemas when required
- Providing a predictable, immutable unit for blue/green deployments

This layer is intentionally:
- Self-contained
- Deterministic
- Environment-agnostic

# ------------------------------------------------------------
#  WHAT THIS LAYER SOLVES
# ------------------------------------------------------------
- The same container runs identically in local, staging, and production.
- Database availability (PostgreSQL vs SQLite) is detected dynamically at runtime.
- Startup logic is deterministic and observable.
- Infrastructure concerns never leak into application logic.

# ------------------------------------------------------------
#  DIRECTORY STRUCTURE
# ------------------------------------------------------------
docker/
├─ app/                     # FastAPI application, ORM models, SRE logic
├─ docs/                    # Runtime documentation & container architecture
├─ Dockerfile               # Container image definition
├─ README.md                # Docker runtime documentation
├─ bootstrap_env.sh         # Environment validation & normalization
├─ entrypoint.sh            # Container startup orchestrator
├─ wait_for_db.py           # Runtime DB selection & availability checker
└─ create_sqlite_tables.py  # SQLite schema bootstrapper

# ------------------------------------------------------------
#  REPOSITORY SNAPSHOT
# ------------------------------------------------------------
docker/
├── Dockerfile
├── README.md
├── app/
│   ├── alembic/
│   ├── alembic.ini
│   ├── bootstrap_env.sh
│   ├── create_sqlite_tables.py
│   ├── crud.py
│   ├── db.py
│   ├── entrypoint.sh
│   ├── local_tz.py
│   ├── main.py
│   ├── models.py
│   ├── reset_alembic.py
│   ├── 
│   ├── schemas.py
│   ├── test.py
│   ├── wait_for_db.py
│   ├── wait_for_db_core.py
│   ├── sre/
│
└── docs/
    ├── files.md
    └── runtime.md

# ------------------------------------------------------------
#  COMPONENT BREAKDOWN
# ------------------------------------------------------------

## app/
- Contains the application runtime itself:
  - FastAPI service
  - SQLAlchemy ORM models
  - CRUD logic and schemas
  - WebSocket manager
  - Health checks and SRE-related logic
- Business logic is fully isolated from infrastructure concerns.
- The application assumes nothing about where it is running (cloud, local, CI, edge).

## bootstrap_env.sh
- Responsible for environment normalization at container startup.
- Responsibilities:
  - Validate required environment variables
  - Apply safe defaults where allowed
  - Prevent undefined or unsafe runtime states

## entrypoint.sh
- Main runtime orchestrator for the container.
- Responsibilities:
  - Source normalized environment variables
  - Wait for database availability
  - Trigger SQLite bootstrap when required
  - Start the FastAPI server
- Controls execution flow only.
- Contains no business logic.

## wait_for_db.py
- Runtime database decision engine.
- Responsibilities:
  - Detect PostgreSQL availability
  - Fall back safely to SQLite when required
  - Retry PostgreSQL connections when configured
  - Export final database configuration to `/tmp/db_env.sh`

## create_sqlite_tables.py
- SQLite schema bootstrapper.
- Responsibilities:
  - Create all tables using SQLAlchemy metadata
  - Run only when SQLite fallback mode is active
  - Remain safe and idempotent for repeated execution

## ../docs/
- Contains runtime and architectural documentation:
  - `runtime.md` — detailed container startup and runtime behavior
  - `files.md` — supporting documentation

# ------------------------------------------------------------
#  DESIGN PRINCIPLE
# ------------------------------------------------------------
Docker knows nothing about Terraform or Ansible.

It assumes:
- The host is ready
- The container is immutable
- Runtime decisions must be safe, observable, and deterministic
