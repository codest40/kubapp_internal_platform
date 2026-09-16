# Observability

The `observability/` directory contains the monitoring and visualization layer of `sys_monitor`.

Its purpose is to provide visibility into the internal state and behavior of the system through metrics collection, storage, querying, and visualization.

## Components

| Directory     | Purpose                                            |
| ------------- | -------------------------------------------------- |
| `grafana/`    | Grafana dashboards and visualization configuration |
| `prometheus/` | Prometheus configuration and metrics collection    |

## Architecture Role

The observability layer consumes metrics produced by the different `sys_monitor` components and makes those metrics available for operational monitoring.

The main flow is:

**sys_monitor components → Prometheus → Grafana**

Prometheus provides the metrics collection and monitoring layer, while Grafana provides visualization and dashboards.

## Directory Structure

```
observability/
├── README.md
├── grafana/
└── prometheus/
```

Each component maintains its own documentation inside its respective directory.

## Scope

This directory is concerned specifically with **observability**.

It does not contain:

* Cloud infrastructure provisioning
* Application event processing
* GitHub event ingestion
* GitOps/Kubernetes collection logic
* Core system discovery logic

Those responsibilities are handled by other parts of `sys_monitor`.

## Documentation

Detailed documentation for each observability component is maintained separately:

* `grafana/README.md` — Grafana configuration, dashboards, and visualization
* `prometheus/README.md` — Prometheus configuration, scraping, and metrics collection
