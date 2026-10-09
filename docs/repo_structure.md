## 4. Repository Structure

```text
kubapp/
├── .github/
│   ├── workflows/              # CI/CD and platform automation workflows
│   └── docs/                   # Workflow and operational documentation
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
│   ├── cloud/
│   │   └── aws/                # AWS infrastructure for sys_monitor
│   ├── codebase/               # Codebase discovery and analysis engine
│   ├── exporters/              # GitHub and GitOps metric exporters
│   ├── observability/          # Prometheus and Grafana configuration
│   └── docs/                   # sys_monitor documentation
│
├── mcp/                        # MCP and AI integration
│
├── account.name                # AWS account/environment identifier
├── .checkov.yaml               # Checkov security configuration
├── .sops.yaml                  # SOPS encryption configuration
├── .trivyignore                # Trivy vulnerability scan exclusions
├── SECURITY.md                 # Security guidance
├── SETUP.md                    # Platform setup guide
├── SOPS.md                     # Secret management guide
├── setup.sh                    # Initial platform setup
├── setup_functions.sh          # Setup helper functions
├── reuse.sh                    # Shared setup/reuse logic
├── README.md                   # Main project documentation
└── LICENCE.md                  # Project licence
```

### Application Onboarding

Applications are onboarded through the platform rather than being tightly coupled to the infrastructure layout.
A dedicated application workspace is be provided for app services:

```text
docker/
└── <application>/
```

Each application can then be discovered, validated, built, registered, and deployed through the KUBAPP platform workflows.
The platform itself remains responsible for the underlying infrastructure, Kubernetes resources, GitOps reconciliation, observability, security, and recovery.
