# SysMonitor Frontend

The SysMonitor frontend is a React dashboard for viewing application health and database connectivity within the KUBAPP development environment.

## Features

- **Overview:** Summarizes application health and database monitoring results.
- **Applications:** Displays registered applications and their readiness and liveness status.
- **Databases:** Displays database connection status and health-check duration.
- **Refresh:** Fetches the latest monitoring results from the backend.
- **Error handling:** Displays loading states and API request errors.

## API Integration

The frontend requests data from the SysMonitor backend through:

| Endpoint | Purpose |
|---|---|
| `/sys-monitor/api/applications` | Retrieves application health results. |
| `/sys-monitor/api/database` | Retrieves database connectivity results. |

In development, Vite proxies these requests to `http://localhost:8000`. In Docker deployments, Nginx proxies them to the `backend` service on port `8000`.

## Running Locally

From the `frontend/` directory:

```bash
npm ci
npm run dev
```

The Vite development server displays the local URL when it starts. Ensure the backend is running on port `8000`.

## Build and Validation

```bash
npm run build
npm run lint
```

- `npm run build` creates the production bundle in `dist/`.
- `npm run lint` runs ESLint.

## Docker

Build the frontend image from the `frontend/` directory:

```bash
docker build -t sys-monitor-frontend .
```

The production image serves the built application through Nginx on port `80` and proxies API requests to the backend service.

The frontend presents monitoring results supplied by the backend; it does not independently probe applications or databases.
