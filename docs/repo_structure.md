## Repository Structure

```text
kubapp/
├── .github/
│   ├── workflows/              # CI/CD and platform automation workflows
│   └── docs/                   # Workflow and operational documentation
│
├── docker/                     # Application onboarding and Config
│   ├── README.md
│   └── <applications>/
│
├── docs/                       # Platform architecture and engineering documentation
│
├── gitops/
│   ├── argocd/                 # Argo CD applications and ingress configuration
│   ├── charts/                 # Reusable Helm charts
│   │   ├── apps/
│   │   ├── ingress/
│   │   └── postgres/
│   ├── envs/                   # Environment-specific application values
│   ├── ingress/                # Environment-specific ingress configuration
│   ├── registry/               # Application and service registry state
│   ├── secret_mgt/             # SOPS-managed GitOps secrets
│   └── state/                  # Platform deployment state
│
├── iac/
│   ├── boot/                   # Initial AWS and GitHub infrastructure bootstrap
│   ├── boot_oidc_only/         # OIDC-only bootstrap path
│   ├── database/               # Database infrastructure and cross-account networking
│   ├── dns/                    # Route 53 and DNS infrastructure
│   ├── infra/                  # Core AWS infrastructure
│   │   ├── envs/
│   │   └── modules/
│   │       ├── acm/
│   │       ├── database/
│   │       ├── efs/
│   │       ├── eks/
│   │       ├── iam-core/
│   │       ├── iam-irsa/
│   │       ├── logging/
│   │       ├── network/
│   │       ├── security/
│   │       └── sg-prep/
│   ├── k8s/                    # Kubernetes cluster configuration
│   └── manifests/              # Kubernetes manifests and platform alerts
│
├── setups/                     # Setup guides
│   ├── SETUP.md                # Platform setup guide
│   ├── SOPS.md                 # Secret management guide
│
├── scripts/
│   ├── ci/                     # Application discovery, validation and build logic
│   ├── cleanups/               # Platform and AWS cleanup operations
│   ├── drifts/                 # GitOps and Terraform drift detection
│   ├── extra/                  # Shared automation helpers
│   ├── github/                 # GitHub-specific automation
│   ├── gitops/                 # GitOps and Argo CD operations
│   ├── platform/               # Platform registry and reconciliation logic
│   └── docs/                   # Script documentation
│
├── sys_monitor/
│   ├── backend/                # Backend services and APIs
│   ├── frontend/               # Frontend applications and interfaces
│   ├── cloud/
│   │   └── aws/                # AWS infrastructure for sys_monitor
│   ├── codebase/               # Codebase discovery and analysis engine
│   ├── exporters/              # GitHub and GitOps metric exporters
│   ├── observability/          # Prometheus and Grafana configuration
│   └── docs/                   # sys_monitor documentation
│
├── account.name                # AWS account/environment identifier
├── .checkov.yaml               # Checkov security configuration
├── .sops.yaml                  # SOPS encryption configuration
├── .trivyignore                # Trivy vulnerability scan exclusions
├── SECURITY.md                 # Security guidance
├── setup.sh                    # Initial platform setup
├── setup_functions.sh          # Setup helper functions
├── reuse.sh                    # Shared setup/reuse logic
├── README.md                   # Main project documentation
└── LICENCE.md                  # Project licence
```
