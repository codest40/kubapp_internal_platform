# KUBAPP — MANIFESTS

The iac/manifests/ layer contains Kubernetes resources that are deployed after the EKS platform has been created.
Unlike iac/infra/, which creates AWS infrastructure, and iac/k8s/, which bootstraps the Kubernetes platform itself, this layer defines KUBAPP-specific Kubernetes configuration and operational policies.
Its current responsibility is primarily Prometheus alerting rules.

## Purpose

The manifests layer provides Kubernetes resources that depend on the already-running KUBAPP cluster.
The flow is:

```
iac/boot
```

   │

   ▼

AWS Terraform backend

   │

   ▼

iac/infra

   │

   ▼

AWS infrastructure + EKS

   │

   ▼

iac/k8s

   │

   ▼

Kubernetes platform services

   │

   ▼

iac/manifests

   │

   ▼

KUBAPP operational policies

This separation keeps the infrastructure foundation independent from application/platform-specific Kubernetes policies.

## What It Defines

-  Prometheus application alerts 
-  Prometheus infrastructure alerts 
-  Prometheus ingress alerts 
-  Test alerts for validating the monitoring pipeline 
-  Environment-specific alerting configuration 

Example:

```
Prometheus
```

    │

    ├── Application Alerts

    │

    ├── Infrastructure Alerts

    │

    ├── Ingress Alerts

    │

    └── Test Alerts

            │

            ▼

       Alertmanager

            │

            ▼

      Notification Channel

## Alerting

### Application Alerts

`alert_app.tf` monitors application-level health:

-  High HTTP 5xx error rate 
-  High p95 request latency 
-  Frequent container restarts 
-  Services with no available endpoints 

These alerts answer:

> **Are the applications running correctly from a user's perspective?**

### Infrastructure Alerts

`alert_infra.tf` monitors Kubernetes and node health:

-  Nodes becoming `NotReady` 
-  Severe memory pressure 
-  Low filesystem capacity 
-  OOMKilled containers 
-  Excessive CPU throttling 

These alerts answer:

> **Is the underlying Kubernetes runtime healthy enough to support workloads?**

### Ingress Alerts

`alert_ingress.tf` monitors traffic entering the platform:

-  Ingress 5xx errors 
-  No incoming traffic 
-  High ingress latency 
-  Backend `502` responses 
-  TLS certificates approaching expiration 

These alerts answer:

> **Is traffic successfully reaching and being served by applications?**

### Test Alert

`alert_test.tf` contains an intentionally firing alert:

```
KubappAlertAlwaysFiring
```

It exists to verify that the monitoring pipeline is functioning:

```
Prometheus
```

   │

   ▼

Alert Rule

   │

   ▼

Alertmanager

   │

   ▼

Notification Channel

This provides a simple operational test for alert routing and notification delivery.

## Why KUBAPP Uses It

KUBAPP separates **platform provisioning** from **platform operational policy**.

The manifests layer allows monitoring and alerting configuration to be changed independently from the underlying EKS infrastructure.

This provides:

-  Independent alert configuration 
-  Environment-specific alerting 
-  Infrastructure monitoring 
-  Application monitoring 
-  Ingress monitoring 
-  Automated alert validation 
-  Infrastructure-as-Code management 

For example, changing an alert threshold does not require changing the EKS infrastructure.

## Terraform Integration

The manifests are managed through Terraform rather than being applied manually with `kubectl`.

The root module conditionally enables the alerting module:

```
module "alerts" {
```

  count  = var.enable\_alerts ? 1 : 0

  source = "./alerts"

}

This allows alerting to be enabled or disabled per environment.

## Remote State Integration

The manifests layer does not recreate the EKS cluster.

Instead, `local.tf` reads outputs from the existing Kubernetes infrastructure state:

```
iac/k8s
```

   │

   ├── Cluster name

   ├── Cluster endpoint

   └── Cluster CA certificate

   │

   ▼

iac/manifests

This allows Terraform to connect to the correct Kubernetes cluster without duplicating cluster configuration.

## Providers

Two providers are available:

| ProviderPurpose |                                                  |
| --------------- | ------------------------------------------------ |
| `AWS`           | AWS context and regional configuration           |
| `Kubernetes`    | Applying Kubernetes resources to the EKS cluster |

The Kubernetes provider authenticates to EKS using:

```
AWS CLI
```

   │

   ▼

aws eks get-token

   │

   ▼

EKS authentication

   │

   ▼

Kubernetes API

No static Kubernetes credentials are stored in the repository.

## Environment Separation

Environment-specific configuration is kept under:

```
envs/
```

└── dev/

    ├── manifests.tfvars

    └── manifests.tfvars.enc

This allows the same manifests layer to be used for different environments while changing only environment-specific values.

The encrypted `.tfvars.enc` file allows sensitive environment configuration to remain encrypted rather than stored as plaintext.

## Directory Structure

```
manifests/


├── alerts/

│   ├── alert\_app.tf

│   ├── alert\_infra.tf

│   ├── alert\_ingress.tf

│   └── alert\_test.tf

│

├── envs/

│   └── dev/

│       ├── manifests.tfvars

│       └── manifests.tfvars.enc

│

├── backend.tf

├── local.tf

├── main.tf

├── outputs.tf

├── providers.tf

├── variables.tf

└── versions.tf
```

## Module Inputs

| InputPurpose              |                                                                     |
| ------------------------- | ------------------------------------------------------------------- |
| `enable_alerts`           | Enables or disables the alerting configuration                      |
| Environment configuration | Provides environment-specific manifests values                      |
| Kubernetes cluster state  | Provides the cluster connection information consumed from `iac/k8s` |

## Outputs

The manifests layer primarily applies Kubernetes operational policies rather than creating infrastructure resources.
Any outputs exposed by the root module can be used by higher-level automation or deployment workflows.

## KUBAPP Role

This layer forms part of KUBAPP's **Kubernetes operational policy and observability layer**.
It defines how the platform should be monitored after the EKS platform has been provisioned, while keeping alerting and operational policies separate from the underlying AWS infrastructure and Kubernetes platform bootstrap.


## Why `manifests/` Is Separate From `k8s/`
KUBAPP separates `manifests/` from `k8s/` because they have different dependency requirements.

The `k8s/` layer is responsible for **bootstrapping the Kubernetes platform itself**. It creates and configures foundational components such as:

- Kubernetes namespaces
- storage classes and CSI drivers
- service accounts
- AWS Load Balancer Controller
- ExternalDNS
- ArgoCD
- Fluent Bit
- Prometheus/Grafana
- cluster readiness dependencies

These components have ordering and dependency relationships that must be satisfied before higher-level Kubernetes resources can be safely applied.

The `manifests/` layer runs **after the Kubernetes platform is ready** and adds resources that depend on those services being available.

For example, the Prometheus alert rules in this layer depend on the monitoring stack already being installed and its `PrometheusRule` CRD being available.

Keeping these resources separate avoids dependency and initialization problems during cluster bootstrap.

```text
k8s/
  Platform bootstrap
       ↓
  EKS dependencies become ready
       ↓
manifests/
  Higher-level Kubernetes resources
  such as Prometheus alerting rules

