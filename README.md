# kubapp

## Project Goals
Kubapp aims to provide a simplified but production-oriented Kubernetes platform on AWS.
Each Section of the project has its own readme file, so this is the outline.
For configuring and initializing KubApp, see [SETUP.md](./SETUP.md).

## The project was built to:
- Automate Kubernetes infrastructure provisioning and management
- Simplify cloud-native operations without overengineering the architecture
- Enable reproducible deployments through Infrastructure as Code and GitOps workflows
- Improve operational visibility with integrated monitoring and observability
- Provide a maintainable file-based platform that is easy to operate, debug, and extend

## The project focuses on:
- Infrastructure as Code
- Continuous Integration/Deployment
- GitOps workflows
- Observability
- Secure cross-account access
- Automated provisioning
- Operational simplicity

## Extra Documentation

- [Architecture](docs/architecture.md)
- [Operations](docs/execution_flow.md)
- [Security](docs/security.md)
- [Observability](docs/observability.md)
- [Information](docs/extra_info.md)


## Full Repository Structure

```text
kubapp/
├── .github/                          # CI/CD automation and GitHub Actions pipelines
│   ├── workflows/                    # Terraform, GitOps, validation, drift, rollback, deployment workflows
│   └── docs/                         # Documentation for CI/CD workflows and pipelines
│
├── docs/                             # Core system documentation
│   ├── execution_flow.md            # End-to-end platform execution flow
│   ├── extra_info.md                # Extended technical notes
│   ├── structure                    # Repository structure notes
│   ├── architecture.md             # System architecture overview
│   ├── security.md                 # Security model (IAM, secrets, policies)
│   ├── observability.md            # Monitoring and SRE design
│   └── README.md                   # Documentation entry point
│
├── scripts/                          # Platform automation and operational control layer
│   ├── functions/                   # Shared shell utilities (logging, validation, checks)
│   ├── activate.sh                 # Full platform bootstrap entrypoint
│   ├── run_tf.sh                   # Terraform execution wrapper
│   ├── bootstrap_gitops.sh         # GitOps initialization (ArgoCD + repo wiring)
│   ├── setup_argocd.sh             # ArgoCD installation and setup
│   ├── validate.sh                 # Pre-deployment validation pipeline
│   ├── drift_state.sh              # Terraform state drift detection
│   ├── drift_gitops.sh             # GitOps drift detection and reconciliation check
│   ├── promote.sh                  # Environment promotion workflow (dev → stage → prod)
│   ├── register_new_svc.sh         # Service onboarding automation
│   ├── remove_app.sh               # Application teardown automation
│   ├── sync_route53.sh             # DNS synchronization (Route53 updates)
│   ├── clean_cluster.sh            # Kubernetes cluster cleanup
│   ├── setup_argocd_local.sh       # Local ArgoCD setup
│   ├── commit.sh                   # Commit helper utility
│   ├── delete_leftovers.sh         # Cleanup of residual resources
│   ├── clean_final.sh              # Final system cleanup workflow
│   ├── aws_cleanup.sh              # AWS resource cleanup automation
│   ├── argocd_login.sh             # ArgoCD authentication helper
│   ├── validate_registry.sh        # Application registry validation
│   ├── tag_stable_deploy.sh        # Stable release tagging
│   ├── encrypt_secrets.sh          # Secret encryption workflow (SOPS)
│   ├── setup_sops.sh               # SOPS setup bootstrap
│   ├── cleanup_logs.sh             # Log cleanup automation
│   ├── unlock_tf.sh                # Terraform state unlock utility
│   ├── get_state_file.sh           # Terraform state inspection
│   ├── validate_gitops.sh          # GitOps validation pipeline
│   ├── create_secrets.sh           # Secret creation workflow
│   ├── apply_argo_secret.py        # ArgoCD secret automation (Python)
│   ├── create_values.sh            # Helm values generation helper
│   ├── validate_vars.sh            # Variable validation utility
│   ├── logger.sh                   # Logging utility
│   ├── check_data.sh               # Data validation utility
│   ├── prechecks.sh                # Pre-deployment checks
│   ├── postchecks.sh               # Post-deployment verification
│   ├── cluster_steps.sh            # Cluster lifecycle orchestration
│   ├── verify_cleanup.sh           # Cleanup verification
│   ├── del_argocd.sh               # ArgoCD deletion utility
│   ├── check_cluster.sh            # Cluster health validation
│   ├── get_cert.sh                 # Certificate retrieval utility
│   ├── find.sh                     # Repo search helper
│   ├── R.md                        # Script reference notes
│   ├── docs/scripts_use.md         # Script usage documentation
│   └── __pycache__/               # Python cache artifacts (apply_argo_secret.py)
│
├── gitops/                           # GitOps declarative deployment layer (ArgoCD + Helm)
│   ├── argocd/                      # ArgoCD applications and appsets
│   ├── charts/                      # Reusable Helm charts
│   │   ├── apps/                   # Generic application deployment chart
│   │   ├── ingress/                # Ingress controller chart
│   │   └── postgres/               # PostgreSQL database chart
│   │
│   ├── registry/                    # Application registry definitions (source of truth)
│   │   └── dev/                    # Dev environment app definitions
│   │       ├── alertmanager.json
│   │       ├── argocd.json
│   │       ├── weather_app.json
│   │       ├── prometheus.json
│   │       ├── admin_app.json
│   │       ├── url_shortener.json
│   │       ├── metrics_app.json
│   │       └── grafana.json
│   │
│   ├── envs/                        # Environment-specific Helm values (dev/stage)
│   ├── ingress/                     # Ingress routing configuration per environment
│   ├── secrets/                    # Encrypted GitOps secrets (SOPS)
│   ├── state/                      # GitOps reconciliation state tracking
│   └── README.md                   # GitOps documentation
│
├── docker/                           # Application layer (microservices platform)
│   ├── weather_app/                # FastAPI weather service + SRE instrumentation
│   ├── admin_app/                  # Node.js admin panel service
│   ├── metrics_app/                # Metrics collector + worker service
│   ├── url_shortener/              # Full-stack URL shortener (frontend + backend)
│   ├── docker-compose.yml          # Local multi-service orchestration
│   └── README.md                   # Docker environment documentation
│
├── sys_monitor/                      # Observability + SRE intelligence platform
│   ├── observability/
│   │   ├── grafana/                # Dashboards (GitOps, GitHub, Codebase, System)
│   │   └── prometheus/             # Metrics + alerting configuration
│   │
│   ├── exporters/
│   │   ├── github/                 # GitHub event streaming exporter
│   │   └── gitops/                 # Kubernetes / GitOps metrics exporter
│   │
│   ├── codebase/                   # Internal platform analysis engine
│   │   ├── runners/               # Modular analysis scripts (drift, security, metrics)
│   │   ├── lib/                   # Runtime utilities (JSON, helpers)
│   │   └── evidence/              # Generated outputs (metrics, drift, validation, etc.)
│   │
│   ├── cloud/                      # Cloud environment testing & real AWS Terraform runs
│   │   ├── aws/                    # Production AWS infrastructure scripts
│   │
│   ├── docker-compose.yml         # Monitoring stack local runtime
│   ├── .env                       # Environment variables for monitoring stack
│   └── README.md                  # Observability system documentation
│
├── iac/                             # Infrastructure-as-Code (Terraform platform layer)
│   ├── boot/                      # Terraform backend bootstrap (S3 + DynamoDB)
│   ├── infra/                     # Core AWS infrastructure modules (EKS, IAM, networking)
│   ├── k8s/                       # Kubernetes platform configuration layer
│   ├── manifests/                # Kubernetes manifests + alert rules
│   └── README.md                 # Infrastructure documentation
│
├── .trivyignore                    # Vulnerability scan exclusions
├── .checkov.yaml                   # Security policy enforcement rules
├── .sops.yaml                      # Secret encryption configuration
├── .gitignore                      # Git ignore rules
└── README.md                       # This file
```
