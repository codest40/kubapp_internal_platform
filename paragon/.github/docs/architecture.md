# Architecture

![KubApp CI/CD Architecture](./architecture.png)

The high-level lifecycle is:

```text
Application Source
       │
       ▼
 GitHub Repository
       │
       ▼
 GitHub Actions
       │
       ├──────────────► Build Docker Images
       │                      │
       │                      ▼
       │                 Docker Registry
       │
       ▼
 GitOps Registry
       │
       ▼
 GitOps Provisioning
       │
       ├──────────────► Values / Secrets / Ingress
       │
       ▼
    Argo CD
       │
       ▼
   Kubernetes / EKS
       │
       ▼
 Runtime Verification
       │
       ├──────────────► Stable Deployment
       │
       └──────────────► Rollback
       
Cleanup / Reconciliation
       │
       ▼
 Remove Orphaned Resources
