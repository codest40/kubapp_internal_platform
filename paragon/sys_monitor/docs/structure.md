# Full Structure

```
sys_monitor/
├── README.md
├── docker-compose.yml
│
├── cloud/
│   └── aws/
│       ├── backend.tf
│       ├── boot/
│       │   ├── outputs.tf
│       │   ├── provider.tf
│       │   ├── runner.sh
│       │   ├── s3.tf
│       │   ├── variables.tf
│       │   └── version.tf
│       │
│       ├── create_env.sh
│       ├── local.tf
│       ├── local_roles.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── route53.tf
│       ├── start.sh
│       ├── start_letsencrypt.sh
│       ├── user_data.sh
│       └── variables.tf
│
├── codebase/
│   ├── README.md
│   ├── docs/
│   ├── evidence/
│   ├── lib/
│   │   ├── json.sh
│   │   └── runtime.sh
│   │
│   └── runners/
│       ├── architecture.sh
│       ├── discovery.sh
│       ├── filesystem.sh
│       ├── filesystem_drift.sh
│       ├── drift.sh
│       ├── metrics.sh
│       ├── runner.sh
│       ├── security.sh
│       ├── validation.sh
│       │
│       └── src/
│           └── app.py
│
├── docs/
│   └── structure.md
│
├── exporters/
│   ├── github/
│   │   └── src/
│   │       ├── app.py
│   │       ├── metrics/
│   │       │   ├── health.py
│   │       │   └── registry.py
│   │       ├── routes/
│   │       │   └── github.py
│   │       └── sre_engine/
│   │           ├── __init__.py
│   │           ├── slo_engine.py
│   │           ├── slo_evaluator.py
│   │           └── slo_policy.py
│   │
│   └── gitops/
│       └── ...
│
└── observability/
    ├── grafana/
    │   ├── dashboards/
    │   └── provisioning/
    │
    └── prometheus/
        ├── prometheus.yml
        └── alerts.yml
