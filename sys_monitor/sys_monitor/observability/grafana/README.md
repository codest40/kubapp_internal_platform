# Grafana

The `grafana/` directory contains the Grafana configuration and dashboards used by `sys_monitor`.

Grafana is the **visualization layer** of the observability stack. It consumes metrics from Prometheus and presents them through dashboards for different parts of the system.

## What It Does

The Grafana configuration provides:

* Prometheus as the default metrics data source.
* Automatic dashboard provisioning.
* A dedicated `System Monitoring` dashboard folder.
* Dashboards for GitHub activity.
* Dashboards for Codebase monitoring.
* Dashboards for GitOps state.

The intended flow is:

```
SysMonitor Components
        │
        ▼
    Prometheus
        │
        ▼
      Grafana
        │
  ┌─────┼─────────────┐
  ▼     ▼             ▼
GitHub Codebase      GitOps
Dashboard Dashboard  Dashboard
```

## Structure

```
grafana/
├── dashboards/
│   ├── github-overview.json
│   ├── codebase-overview.json
│   └── gitops-overview.json
│
└── provisioning/
    ├── datasources/
    │   └── datasource.yml
    │
    └── dashboards/
        └── dashboards.yml
```

## Dashboards

### GitHub Overview

`dashboards/github-overview.json`

Provides visualization for metrics produced by the GitHub exporter.

This dashboard is intended to provide visibility into GitHub activity and the reliability signals generated from GitHub events and workflows.

### Codebase Overview

`dashboards/codebase-overview.json`

Provides visualization for metrics produced by the codebase monitoring component.

This dashboard represents the internal state and activity of the monitored codebase.

### GitOps Overview

`dashboards/gitops-overview.json`

Provides visualization for metrics produced by the GitOps exporter.

This includes visibility into GitOps application state, synchronization, drift, and convergence.

## Prometheus Data Source

The Prometheus data source is provisioned automatically through:

```
provisioning/datasources/datasource.yml
```

The configured Prometheus endpoint is:

```
http://prometheus:9090
```

Prometheus is configured as the **default Grafana data source**.

Using the Docker service name rather than `localhost` is intentional because Grafana and Prometheus communicate over the container network.

## Dashboard Provisioning

Dashboard provisioning is defined in:

```
provisioning/dashboards/dashboards.yml
```

Grafana is configured to automatically load dashboards from:

```
/var/lib/grafana/dashboards
```

The dashboards are placed into the:

```
System Monitoring
```

folder.

The provisioning configuration also enables Grafana to detect dashboard changes periodically.

The current update interval is:

```
5 seconds
```

This means dashboards can be updated without manually importing them through the Grafana UI.

## Why Provision Dashboards

The dashboards are stored as files rather than being created manually through the Grafana interface.

This makes the monitoring configuration:

* Version controlled.
* Reproducible.
* Deployable with the rest of `sys_monitor`.
* Easier to maintain.
* Consistent across environments.

Grafana therefore becomes part of the application's infrastructure/configuration rather than relying on manually configured state.

## Role Within SysMonitor

Grafana is the final visualization layer.

Different `sys_monitor` components produce different types of signals:

| Component           | Observability Signal                |
| ------------------- | ----------------------------------- |
| GitHub exporter     | GitHub activity and SRE/SLO signals |
| Codebase monitoring | Internal codebase/system activity   |
| GitOps exporter     | ArgoCD and Kubernetes GitOps state  |
| Prometheus          | Collects and stores the metrics     |
| Grafana             | Visualizes the metrics              |

The overall observability flow is:

```
Collectors / Exporters
        │
        ▼
    Prometheus
        │
        ▼
      Grafana
        │
        ▼
  Operational View
```

## Configuration Boundary

The `grafana/` directory is responsible for **Grafana configuration and visualization**.

It does not define:

* Metric collection logic.
* GitHub webhook processing.
* GitOps/Kubernetes collection.
* Codebase discovery.
* AWS infrastructure.
* Prometheus scraping logic.

Those responsibilities belong to their respective components.

## Dashboard Documentation

Each dashboard is maintained as a version-controlled JSON definition.

The three current dashboards are:

* `github-overview.json`
* `codebase-overview.json`
* `gitops-overview.json`

The dashboards themselves should be treated as the visualization definitions, while this README documents how Grafana is configured and how it fits into `sys_monitor`.
