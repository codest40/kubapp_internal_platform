# Exporters

The `exporters/` directory contains services that collect or expose information from external systems and make that information available to SysMonitor and its observability layer.

The exporters act as integration points between SysMonitor and systems that exist outside the core codebase analysis layer.

## Responsibilities

The exporter layer handles:

* Collecting information from external platforms.
* Converting external system state into metrics.
* Exposing metrics through HTTP endpoints.
* Providing system-specific integrations without placing that logic inside the core monitoring or analysis components.

## Structure

```text
exporters/
├── github/
│   └── ...
│
└── gitops/
    └── ...
```

## Current Exporters

| Exporter  | Purpose                                                      |
| --------- | ------------------------------------------------------------ |
| `github/` | Collects and exposes GitHub-related information and metrics. |
| `gitops/` | Collects and exposes GitOps-related information and metrics. |

Each exporter is maintained independently because the data source, API integration, collection logic, and metrics exposed by each system can differ.

## Exporter Model

The general flow is:

```text
External System
      │
      ▼
   Exporter
      │
      ▼
   Metrics
      │
      ▼
  Prometheus
      │
      ▼
Grafana / Alerts
```

The exporters therefore complement the `codebase/` layer.

While `codebase/` analyzes **SysMonitor's own repository**, exporters provide visibility into **systems outside that repository**, such as GitHub and GitOps infrastructure.

Provider-specific and exporter-specific implementation details are documented inside each exporter directory.
