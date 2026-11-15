# SysMonitor Backend

The SysMonitor backend is a FastAPI service that exposes application health and database connectivity information to the frontend.

## Responsibilities

- **Application monitoring:** Checks registered applications through their configured readiness and liveness HTTP endpoints.
- **Database monitoring:** Tests connectivity to the KUBAPP PostgreSQL database using `SELECT 1` and records query response time.
- **API service:** Returns monitoring results as JSON.
- **Configuration:** Loads server, CORS, and database settings from environment variables and `.env`.

## API Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /` | Returns service name, version, and status. |
| `GET /health` | Reports backend service health. |
| `GET /sys-monitor/api/applications` | Returns application health checks and aggregate counts. |
| `GET /sys-monitor/api/database` | Returns PostgreSQL connectivity status and check duration. |

The API prefix is configurable through `API_PREFIX`.

## Application Registry

Registered applications are defined in `state/app_endpoints.json`. The data is supplied by CI component run. Each entry can specify:

- `url`: Application URL.
- `readiness`: Readiness endpoint.
- `liveness`: Liveness endpoint.

Any HTTP 2xx response is considered successful. Checks use a five-second request timeout. When both readiness and liveness endpoints are configured, both must succeed for the application to be reported healthy.

## Configuration

Settings are loaded by `config.py`. Important environment variables include:

| Variable | Purpose |
|---|---|
| `APP_NAME` | Service name. |
| `APP_VERSION` | Service version. |
| `ENVIRONMENT` | Runtime environment. |
| `DEBUG` | Enables debug mode and Uvicorn reload when running through `main.py`. |
| `API_PREFIX` | Monitoring API prefix. |
| `HOST` / `PORT` | Server bind address and port. |
| `CORS_ORIGINS` | Comma-separated allowed origins. |
| `DB_HOST` / `DB_PORT` | PostgreSQL host and port. |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` | Database connection credentials. |
| `DB_CONNECT_TIMEOUT` | Database connection timeout in seconds. |
| `DB_SSLMODE` | PostgreSQL SSL mode. |

Database monitoring requires the database connection settings to be configured. Keep credentials out of source control.

## Running Locally

From the `backend/` directory:

```bash
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

## Docker

Build and run the backend from the `backend/` directory:

```bash
docker build -t sys-monitor-backend .
docker run --rm -p 8000:8000 --env-file .env sys-monitor-backend
```

Ensure the container has network access to the registered application endpoints and PostgreSQL database.

## Current Scope

The backend currently provides HTTP-based application health checks and a PostgreSQL connectivity check. These checks do not, by themselves, establish full application correctness, database performance, or overall infrastructure health.
