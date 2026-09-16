# kubapp

## Project Goals
Kubapp provides a production-oriented Kubernetes platform on AWS.

## The project was built to:
- Automate Kubernetes infrastructure provisioning and management
- Simplify cloud-native operations without overengineering the architecture
- Enable reproducible deployments through Infrastructure as Code and GitOps workflows
- Improve operational visibility with integrated monitoring and observability
- Provide a maintainable platform that is easy to operate, debug, and extend

## The project focuses on:
- Infrastructure as Code
- GitOps workflows
- Observability
- Secure cross-account access
- Automated provisioning
- Operational simplicity

## Documentation

- [Architecture](docs/architecture.md)
- [Operations](docs/execution_flow.md)
- [Security](docs/security.md)
- [Observability](docs/observability.md)
- [GitOps](gitops/README.md)
- [Workflows](.github/docs/README.md)
- [Infomation](docs/extra_info.md)


## Tools Used

- Kubernetes
- Terraform
- Helm
- AWS EKS
- Docker
- GitHub Actions
- Prometheus
- Grafana
- Argocd
- Route53
- IAM / STS


## Repository Structure

```text
kubapp/
├── .github/                    # GitHub Actions workflows and automation
│   ├── workflows/              # CI/CD, Terraform, GitOps, validation, rollback workflows
│   └── docs/                   # GitHub workflow documentation
│
├── docs/                       # Core project documentation
│   ├── system_flow.md          # System workflow and operational flow
│   ├── exec_steps.md           # Execution and deployment steps
│   ├── structure               # Repository structure notes
│   └── cmds                    # Operational commands reference
│
├── scripts/                    # Platform automation and operational scripts
│   ├── functions/              # Shared shell utility functions
│   ├── activate.sh             # Main platform activation workflow
│   ├── run_tf.sh               # Terraform execution wrapper
│   ├── bootstrap_gitops.sh     # GitOps bootstrap automation
│   ├── setup_argocd.sh         # ArgoCD installation and setup
│   ├── validate.sh             # Validation and precheck workflows
│   ├── drift_state.sh          # Terraform drift detection
│   ├── drift_gitops.sh         # GitOps drift validation
│   ├── promote.sh              # Deployment promotion workflow
│   ├── register_new_svc.sh     # New application registration
│   ├── remove_app.sh           # Application removal automation
│   ├── sync_route53.sh         # Route53 synchronization
│   └── cleanup utilities       # Cluster, AWS, and log cleanup scripts
│
├── iac/                        # Infrastructure as Code (Terraform)
│   ├── boot/                   # Bootstrap backend infrastructure
│   │   ├── s3.tf               # Terraform state bucket
│   │   └── dynamodb.tf         # Terraform state locking
│   │
│   ├── infra/                  # Core AWS infrastructure provisioning
│   │   ├── modules/
│   │   │   ├── network/        # VPC, subnets, networking
│   │   │   ├── eks/            # EKS cluster and node groups
│   │   │   ├── security/       # Security groups and controls
│   │   │   ├── iam-core/       # Core IAM roles and policies
│   │   │   ├── iam-irsa/       # IAM Roles for Service Accounts
│   │   │   ├── logging/        # Logging infrastructure
│   │   │   ├── efs/            # Persistent storage
│   │   │   └── acm/            # TLS certificate management
│   │   │
│   │   └── envs/               # Environment-specific Terraform variables
│   │
│   ├── k8s/                    # Kubernetes platform resources
│   │   ├── helm.tf             # Helm-based deployments
│   │   ├── namespaces.tf       # Namespace management
│   │   ├── sa.tf               # Service accounts
│   │   ├── storage_class.tf    # Persistent storage classes
│   │   └── fargate_log.tf      # Fargate logging configuration
│   │
│   └── manifests/              # Kubernetes manifest and alert provisioning
│       └── alerts/             # Infrastructure and application alerts
│
├── gitops/                     # GitOps configuration and deployment state
│   ├── argocd/                 # ArgoCD root applications and appsets
│   ├── charts/                 # Shared Helm charts
│   │   ├── apps/               # Generic application deployment chart
│   │   ├── ingress/            # Ingress controller chart
│   │   └── postgres/           # PostgreSQL deployment chart
│   │
│   ├── envs/                   # Environment-specific application values
│   ├── ingress/                # Ingress routing configuration
│   ├── registry/               # Application registry definitions
│   ├── secrets/                # GitOps-managed secrets
│   └── state/                  # GitOps deployment state tracking
│
├── docker/                     # Application source code and containerization
│   ├── docker-compose.yml      # Local multi-service development
│   └── docs/                   # Docker-specific documentation
│
├── sys_monitor/                # External monitoring and observability system
│   ├── observability/
│   │   ├── grafana/            # Grafana dashboards and provisioning
│   │   └── prometheus/         # Prometheus configuration
│   │
│   ├── exporters/
│   │   ├── github/             # GitHub activity exporter
│   │   └── gitops/             # GitOps metrics exporter
│   │
│   ├── infra/aws/              # Monitoring infrastructure provisioning
│   └── docker-compose.yml      # Monitoring stack local runtime
│
├── .sops.yaml                  # SOPS encryption configuration
├── .checkov.yaml               # Checkov policy configuration
├── .trivyignore                # Trivy scan exclusions
└── README.md                   # Main project documentation
```
