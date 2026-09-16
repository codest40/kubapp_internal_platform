# KubApp CI/CD

KubApp uses GitHub Actions to automate the application lifecycle from
source changes through container image creation, GitOps registry
generation, Kubernetes deployment, verification, rollback, and cleanup.

## CI/CD Architecture

The architecture and end-to-end workflow are documented in:

* [CI/CD Architecture](./architecture.md)
* [Execution Flow](./flow.md)

## Pipeline Stages

1. **Continuous Integration**
2. **Platform Build**
3. **GitOps Provisioning**
4. **Deployment**
5. **Runtime Verification**
6. **Stable Deployment**
7. **Rollback**
8. **Cleanup**

## Workflow Categories

| Category               | Workflows                                                                                                                                                       |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pipeline orchestration | [`activate_pipeline.yml`](../workflows/activate_pipeline.yml)                                                                                                   |
| Continuous Integration | [`ci.yml`](../workflows/ci.yml)                                                                                                                                 |
| Platform build         | [`build.yml`](../workflows/build.yml)                                                                                                                           |
| GitOps provisioning    | [`add_new_app.yml`](../workflows/add_new_app.yml), [`validate_gitops.yml`](../workflows/validate_gitops.yml)                                                    |
| Deployment             | [`setup_argocd.yml`](../workflows/setup_argocd.yml), [`verify_runtime.yml`](../workflows/verify_runtime.yml)                                                    |
| Stable deployment      | [`create_stable_deploy.yml`](../workflows/create_stable_deploy.yml), [`get_stable_deploy.yml`](../workflows/get_stable_deploy.yml)                              |
| Rollback               | [`rollback.yml`](../workflows/rollback.yml)                                                                                                                     |
| Cleanup                | [`clean_argocd.yml`](../workflows/clean_argocd.yml), [`remove_app.yml`](../workflows/remove_app.yml), [`remove_svc.yml`](../workflows/remove_svc.yml)           |
| Operations             | [`unlock.yml`](../workflows/unlock.yml)                                                                                  |
| Infrastructure         | [`terraform.yml`](../workflows/terraform.yml), [`terraform_sub.yml`](../workflows/terraform_sub.yml), [`terraform_drift.yml`](../workflows/terraform_drift.yml) |
| Other                  | [`docker-push.yml`](../workflows/docker-push.yml), [`update.yml`](../workflows/update.yml)                                                                      |

## Documentation

Detailed documentation for each part of the CI/CD system is maintained
under `docs/`.

### Architecture & Flow

* [CI/CD Architecture](./architecture.md) — Overall CI/CD architecture, workflow relationships, and major components.
* [Execution Flow](./flow.md) — End-to-end flow from CI through platform build, GitOps provisioning, deployment, verification, and rollback.

### Build & Registry

* [Build Pipeline](./build.md) — Platform registry build and registry artifact generation.
* [Registry Generation](./registry.md) — How build artifacts are transformed into the GitOps registry and how platform/backend services are registered.

### GitOps & Application Provisioning

* [GitOps](../../gitops/README.md) — Application metadata, values generation, secret injection, ingress registration, validation, and GitOps commits.
* [Application Provisioning](./add_new_app.md) — Detailed behavior of the application provisioning workflow.
* [Ingress Management](./ingress.md) — Shared ingress registration and service removal.

### Deployment & Verification

* [Deployment](./deployment.md) — Argo CD setup, application deployment, and environment-specific deployment behavior.
* [Runtime Verification](./verification.md) — Post-deployment health checks and runtime validation.

### Rollback

* [Rollback](./rollback.md) — Stable deployment identification, target rollback, and full rollback.
* [Stable Deployment](./stable_deploy.md) — How stable deployments are created and retrieved.

### Cleanup & Reconciliation

* [Cleanup](./cleanup.md) — Cluster cleanup and removal of Kubernetes resources.
* [Application Reconciliation](./reconciliation.md) — Detection and removal of orphaned application resources.
* [Service Removal](./remove_service.md) — Removing services from the shared ingress and triggering downstream reconciliation.

### Operations & Debugging

* [Operational Workflows](./operations.md) — Manual operational actions and operational troubleshooting.

## Workflow Reference

For the complete list of GitHub Actions workflows, see the
[`../workflows/`](../workflows/) directory.

| Workflow                                                            | Purpose                                                      |
| ------------------------------------------------------------------- | ------------------------------------------------------------ |
| [`activate_pipeline.yml`](../workflows/activate_pipeline.yml)       | Manually orchestrates the major pipeline stages              |
| [`ci.yml`](../workflows/ci.yml)                                     | Runs application continuous integration                      |
| [`build.yml`](../workflows/build.yml)                               | Builds the platform registry and generates registry metadata |
| [`add_new_app.yml`](../workflows/add_new_app.yml)                   | Provisions applications into the GitOps structure            |
| [`validate_gitops.yml`](../workflows/validate_gitops.yml)           | Validates the generated GitOps state                         |
| [`setup_argocd.yml`](../workflows/setup_argocd.yml)                 | Configures Argo CD and deployment resources                  |
| [`verify_runtime.yml`](../workflows/verify_runtime.yml)             | Verifies deployed application runtime state                  |
| [`create_stable_deploy.yml`](../workflows/create_stable_deploy.yml) | Promotes a commit as a stable deployment                     |
| [`get_stable_deploy.yml`](../workflows/get_stable_deploy.yml)       | Retrieves the latest stable deployment information           |
| [`rollback.yml`](../workflows/rollback.yml)                         | Performs target or full rollback                             |
| [`clean_argocd.yml`](../workflows/clean_argocd.yml)                 | Cleans Kubernetes and Argo CD resources                      |
| [`remove_app.yml`](../workflows/remove_app.yml)                     | Reconciles and removes orphaned applications                 |
| [`remove_svc.yml`](../workflows/remove_svc.yml)                     | Removes services from shared ingress                         |
| [`fixer.yml`](../workflows/fixer.yml)                               | Provides controlled operational troubleshooting              |
| [`unlock.yml`](../workflows/unlock.yml)                             | Handles workflow or infrastructure lock operations           |
| [`terraform.yml`](../workflows/terraform.yml)                       | Runs Terraform infrastructure operations                     |
| [`terraform_sub.yml`](../workflows/terraform_sub.yml)               | Runs Terraform sub-operations                                |
| [`terraform_drift.yml`](../workflows/terraform_drift.yml)           | Detects Terraform infrastructure drift                       |
| [`docker-push.yml`](../workflows/docker-push.yml)                   | Manually builds and pushes a Docker image                    |
| [`update.yml`](../workflows/update.yml)                             | Performs repository update operations                        |

## Design Principles

KubApp CI/CD is designed around:

* **Git-driven automation** — GitHub is the source of workflow and GitOps changes.
* **Immutable container images** — Builds produce uniquely tagged images while maintaining a `latest` tag.
* **GitOps-based deployment** — Kubernetes deployment state is generated and managed through Git.
* **Environment isolation** — Development and production workflows explicitly identify their target environment.
* **Automated reconciliation** — Orphaned applications and stale resources can be detected and removed.
* **Controlled rollback** — Stable deployments are identified and can be restored without rebuilding application images.
* **Operational safety** — Destructive operations include explicit safety checks and production protections.
* **Centralized ingress** — Applications are registered into the shared ingress configuration rather than creating independent ingress infrastructure for every application.
* **Secret management with SOPS** — Secrets are handled through SOPS/AGE encryption; plaintext values that may appear in local development files are local-only and are not committed or used outside the local environment.

## Directory Structure

```text
.github/
├── README.md
├── github-app-manifest.json
├── docs/
│   ├── README.md
│   ├── architecture.md
│   ├── flow.md
│   ├── build.md
│   ├── registry.md
│   ├── gitops.md
│   ├── add_new_app.md
│   ├── ingress.md
│   ├── deployment.md
│   ├── verification.md
│   ├── rollback.md
│   ├── stable_deploy.md
│   ├── cleanup.md
│   ├── reconciliation.md
│   ├── remove_service.md
│   ├── operations.md
│   └── artifacts.md
└── workflows/
    ├── activate_pipeline.yml
    ├── add_new_app.yml
    ├── app_artifacts.yml
    ├── build.yml
    ├── ci.yml
    ├── clean_argocd.yml
    ├── create_stable_deploy.yml
    ├── docker-push.yml
    ├── get_stable_deploy.yml
    ├── remove_app.yml
    ├── remove_svc.yml
    ├── rollback.yml
    ├── setup_argocd.yml
    ├── terraform.yml
    ├── terraform_drift.yml
    ├── terraform_sub.yml
    ├── unlock.yml
    ├── update.yml
    ├── validate_gitops.yml
    └── verify_runtime.yml
```

