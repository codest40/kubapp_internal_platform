# Observability

The `observability/` directory contains the monitoring and visualization layer of `sys_monitor`.

Its purpose is to expose the internal state and health signals produced by the system through **Prometheus** and **Grafana**.

The observability layer is intentionally separated from the collectors and exporters so that monitoring, alerting, and visualization can evolve independently from the components generating the underlying metrics.

## Structure

```text
observability/
├── grafana/
│   ├── dashboards/
│   └── provisioning/
│
└── prometheus/
    ├── alerts.yml
    └── prometheus.yml
```

## Components

### Grafana

The `grafana/` directory contains the Grafana configuration used to visualize `sys_monitor` metrics.

It includes:

* Pre-built dashboards for different system-monitoring domains.
* Prometheus datasource provisioning.
* Dashboard provisioning configuration.

The dashboards currently cover:

* GitHub activity and SRE signals.
* Codebase monitoring.
* GitOps state and convergence.

Detailed Grafana documentation is maintained in:

`observability/grafana/README.md`

### Prometheus

The `prometheus/` directory contains the Prometheus configuration for collecting and evaluating `sys_monitor` metrics.

It includes:

* Scrape configuration.
* Alerting rules.
* Targets for the GitHub exporter.
* Targets for the SRE engine.
* Targets for the GitOps exporter.
* Targets for the codebase exporter.

Detailed Prometheus documentation is maintained in:

`observability/prometheus/README.md`

## Observability Flow

The high-level flow is:

```text
sys_monitor Components
        │
        ▼
     Metrics
        │
        ▼
   Prometheus
      │   │
      │   └── Alert Rules
      │
      ▼
    Grafana
      │
      ▼
Dashboards / Visualization
```

## Design Principle

The observability layer does not own the logic that produces the underlying system signals.

Instead:

* **Collectors and exporters** produce metrics.
* **Prometheus** collects and evaluates those metrics.
* **Alert rules** identify important conditions.
* **Grafana** visualizes the resulting system state.

This separation keeps `sys_monitor` modular and allows individual monitoring components to change without requiring the entire observability layer to be redesigned.
