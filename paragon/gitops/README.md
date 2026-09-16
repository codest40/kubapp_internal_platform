# KUBAPP — GITOPS LAYER

## Overview

The `gitops/` directory contains the GitOps control plane for KUBAPP.

It defines the desired runtime state of applications and supporting Kubernetes resources using:

- ArgoCD
- ApplicationSets
- Helm
- Environment-specific values
- SOPS-encrypted secrets

The core principle is:

    Git defines desired state → ArgoCD reconciles the cluster

Changes to application configuration are therefore made through Git rather than manually applying Kubernetes manifests.

## Architecture

The GitOps layer is organized into several responsibilities:

    registry/
        ↓
    Service definitions
        ↓
    envs/
        ↓
    Environment-specific application configuration
        ↓
    charts/
        ↓
    Reusable Helm templates
        ↓
    argocd/
        ↓
    ArgoCD Applications and ApplicationSets
        ↓
    Kubernetes cluster

Supporting configuration is provided through:

    secrets/
        ↓
    SOPS-encrypted secrets

    ingress/
        ↓
    Environment-specific ingress configuration

The main deployment flow is:

    Git
      ↓
    ArgoCD
      ↓
    ApplicationSet
      ↓
    Helm
      ↓
    Kubernetes resources

## Registry

Path:

    gitops/registry/

The registry acts as the service catalog for KUBAPP workloads.

It provides a central place to describe application characteristics used by the deployment workflow.

Depending on the service, the registry can contain information such as:

- Service name
- Workload type
- Compute type
- Container image
- Image tag
- Ports
- Monitoring requirements
- Storage requirements
- Runtime configuration

The registry helps keep service information consistent instead of duplicating the same information across deployment configuration.

The general model is:

    Service Registry
          ↓
    Application Configuration
          ↓
    Helm Chart
          ↓
    Kubernetes

## Environment Configuration

Path:

    gitops/envs/

Environment configuration contains the runtime values required by individual applications.

Current structure:

    envs/
    └── dev/
        └── apps/
            ├── admin/
            │   └── values.yaml
            ├── metrics/
            │   └── values.yaml
            ├── urlshortener/
            │   └── values.yaml
            └── weather/
                └── values.yaml

These files define application-specific settings such as:

- Replica count
- Container image
- Image tag
- Service ports
- Resource requests and limits
- Readiness probes
- Liveness probes
- Startup probes
- HPA configuration
- ServiceAccount configuration
- IAM role association
- Storage
- Node placement
- Tolerations
- Monitoring configuration

This allows the same Helm chart to be reused for multiple applications while each application supplies its own configuration.

The model is:

    One Helm chart
          +
    Different values
          ↓
    Multiple applications

## Helm Charts

Path:

    gitops/charts/

The charts directory contains reusable Helm charts.

Instead of maintaining separate Kubernetes resources for every application, KUBAPP uses reusable templates.

Current charts include:

- `apps/`
- `ingress/`
- `postgres/`

### Application Chart

Path:

    gitops/charts/apps/

The application chart provides common Kubernetes resources required by KUBAPP workloads.

It currently supports:

- Deployment
- Service
- HorizontalPodAutoscaler
- ServiceAccount
- ServiceMonitor
- Readiness probes
- Liveness probes
- Startup probes
- Resource requests and limits
- Security contexts
- Volumes and volume mounts
- Node selectors
- Tolerations
- Environment variables

Application-specific values are supplied from:

    gitops/envs/<environment>/apps/<service>/values.yaml

This provides a reusable application deployment model.

### Ingress Chart

Path:

    gitops/charts/ingress/

This chart manages Kubernetes Ingress resources used with the AWS Application Load Balancer integration.

It supports:

- Path-based routing
- Subdomain routing
- HTTPS listeners
- TLS certificates
- ALB grouping
- Health-check configuration
- Multiple backend services

Example path-based routing:

    /weather
    /metrics
    /admin
    /urlshortener

Subdomain routing can also be enabled:

    weather.domain.com
    metrics.domain.com
    admin.domain.com

Shared ALB grouping is supported through:

    alb.ingress.kubernetes.io/group.name

This allows multiple ingress resources to participate in the same logical ALB configuration.

### PostgreSQL Chart

Path:

    gitops/charts/postgres/

This chart provides a reusable PostgreSQL deployment definition for workloads that require an in-cluster PostgreSQL instance.

It defines:

- PostgreSQL Deployment
- PersistentVolumeClaim
- Kubernetes Secret
- ClusterIP Service

PostgreSQL data is stored using a PersistentVolumeClaim rather than relying only on the container filesystem.

Database credentials are supplied through Kubernetes Secrets.

## ArgoCD

Path:

    gitops/argocd/

ArgoCD is the GitOps reconciliation engine.

Its responsibility is to continuously compare:

    Git desired state
            VS
    Kubernetes actual state

and reconcile differences.

The general model is:

    Git repository
          ↓
       ArgoCD
          ↓
    Helm rendering
          ↓
    Kubernetes

This removes the need to manually run `kubectl apply` for normal application deployments.

### ApplicationSet — Applications

File:

    gitops/argocd/appset.yaml

The application ApplicationSet dynamically discovers application directories under:

    gitops/envs/dev/apps/*

Each discovered application becomes an ArgoCD Application.

For example:

    envs/dev/apps/weather/
    envs/dev/apps/metrics/
    envs/dev/apps/admin/

can become separate ArgoCD applications.

The generated applications use:

    gitops/charts/apps

as the reusable Helm chart and load the corresponding application's `values.yaml`.

Adding a new application can therefore follow the same deployment pattern without manually creating a separate ArgoCD application definition.

### ApplicationSet — Ingress

File:

    gitops/argocd/ingress.yaml

This ApplicationSet manages ingress configurations for different KUBAPP components.

Current stacks include:

- `dev`
- `monitoring`
- `argocd`

Each stack uses the reusable ingress Helm chart with its own environment-specific values.

This keeps ingress configuration centralized while allowing different services and namespaces to use the same chart.

## ArgoCD Synchronization

Applications are configured for automated synchronization.

Automated synchronization provides:

- Automatic deployment of Git changes
- Automatic pruning of removed resources
- Self-healing when runtime state differs from Git

The deployment model is:

    Git change
        ↓
    ArgoCD detects change
        ↓
    Helm renders desired resources
        ↓
    Kubernetes is updated

If a managed resource is changed manually in the cluster, ArgoCD can detect the difference and restore the Git-defined state.

## Secrets

Path:

    gitops/secrets/

KUBAPP uses SOPS with age encryption for secret management.

Secrets are encrypted before being stored in Git.

Examples include:

- ArgoCD GitHub App credentials
- Grafana administrator credentials
- Application secrets

Encrypted values appear in the repository as SOPS ciphertext rather than plaintext credentials.

The encryption metadata is committed with the file, while the private key required to decrypt the secret remains outside the repository.

The security principle is:

    Secrets may exist in configuration files,
    but plaintext credentials should never be committed
    to the repository.

Plaintext values may exist temporarily in local development or testing environments, but they are not part of the committed GitOps state.

## Ingress Configuration

Path:

    gitops/ingress/

This directory contains environment-specific ingress values.

Current structure:

    ingress/
    ├── dev/
    │   ├── argocd.yaml
    │   ├── monitoring.yaml
    │   └── values.yaml
    │
    └── prod/
        └── values.yaml

The configuration determines which services are exposed through the ALB and how traffic is routed.

Examples include:

- Application services
- Grafana
- Prometheus
- Alertmanager
- ArgoCD

The ingress chart consumes these values and generates the corresponding Kubernetes Ingress resources.

## Observability Integration

KUBAPP integrates application deployments with the monitoring stack through the `ServiceMonitor` resource.

Applications can enable monitoring through:

    serviceMonitor:
      enabled: true

When enabled, the reusable application chart creates a `ServiceMonitor` that tells Prometheus where to collect application metrics.

The flow is:

    Application
        ↓
    /metrics endpoint
        ↓
    ServiceMonitor
        ↓
    Prometheus
        ↓
    Grafana / Alertmanager

This allows monitoring to be enabled as part of application configuration instead of manually configuring every application in the monitoring system.

## Application Security

The reusable application chart provides secure defaults for workloads.

These include:

- `runAsNonRoot`
- `seccomp` with `RuntimeDefault`
- Disabled privilege escalation
- Read-only root filesystem
- Dropped Linux capabilities
- Explicit non-root user IDs

Applications can therefore inherit a common security baseline while still providing application-specific values where required.

## Resource Management

Application values define Kubernetes resource requests and limits.

Example:

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 300m
        memory: 256Mi

These values provide Kubernetes with the information required for scheduling and resource enforcement.

Applications can also enable HorizontalPodAutoscaling:

    hpa:
      enabled: true

This allows replicas to scale based on configured CPU and memory utilization.

## Health Checks

The application chart supports:

- Readiness probes
- Liveness probes
- Startup probes

Readiness determines whether a pod should receive traffic.

Liveness determines whether a container is still healthy.

Startup provides additional protection for applications that require time to initialize.

Example:

    readiness → /health
    liveness  → /live

This allows Kubernetes to make routing and recovery decisions based on application health.

## Deployment Flow

The normal GitOps deployment flow is:

    1. Application code is built
       ↓
    2. CI produces a container image
       ↓
    3. Application image reference is updated
       in GitOps configuration
       ↓
    4. Change is committed to Git
       ↓
    5. ArgoCD detects the Git change
       ↓
    6. ApplicationSet identifies the affected application
       ↓
    7. Helm renders the Kubernetes resources
       ↓
    8. ArgoCD synchronizes the resources
       ↓
    9. Kubernetes starts or updates the workload
       ↓
    10. Health checks and monitoring verify the deployment

The resulting model is:

          Git
           │
           ▼
        ArgoCD
           │
           ▼
      ApplicationSet
           │
           ▼
          Helm
           │
           ▼
      Kubernetes
           │
           ├── Applications
           ├── Services
           ├── HPA
           ├── Ingress
           └── Monitoring

## Directory Structure

    gitops/
    ├── argocd/
    │   ├── appset.yaml
    │   └── ingress.yaml
    │
    ├── charts/
    │   ├── apps/
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       ├── deployment.yaml
    │   │       ├── hpa.yaml
    │   │       ├── sa.yaml
    │   │       ├── service.yaml
    │   │       └── servicemonitor.yaml
    │   │
    │   ├── ingress/
    │   │   ├── Chart.yaml
    │   │   ├── values.yaml
    │   │   └── templates/
    │   │       └── ingress.yaml
    │   │
    │   └── postgres/
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           ├── deployment.yaml
    │           ├── pvc.yaml
    │           ├── secret.yaml
    │           └── service.yaml
    │
    ├── envs/
    │   └── dev/
    │       └── apps/
    │           ├── admin/
    │           │   └── values.yaml
    │           ├── metrics/
    │           │   └── values.yaml
    │           ├── urlshortener/
    │           │   └── values.yaml
    │           └── weather/
    │               └── values.yaml
    │
    ├── ingress/
    │   ├── dev/
    │   │   ├── argocd.yaml
    │   │   ├── monitoring.yaml
    │   │   └── values.yaml
    │   └── prod/
    │       └── values.yaml
    │
    ├── registry/
    │   └── service definitions
    │
    ├── secrets/
    │   ├── github-repo-secret.yaml
    │   └── grafana-secret.yaml
    │
    └── README.md

## Summary

The KUBAPP GitOps layer provides a declarative deployment model for Kubernetes workloads.

Its main building blocks are:

| Component | Responsibility |
|---|---|
| Registry | Central service definitions |
| Environment values | Application-specific runtime configuration |
| Helm | Reusable Kubernetes templates |
| ArgoCD | Continuous reconciliation from Git |
| ApplicationSets | Dynamic ArgoCD Application generation |
| SOPS | Encrypted secret management |
| Ingress configuration | ALB routing and service exposure |
| ServiceMonitor | Application observability |

The core principle is:

    Git is the source of truth.

ArgoCD continuously works to make the Kubernetes runtime match the state defined in Git.
