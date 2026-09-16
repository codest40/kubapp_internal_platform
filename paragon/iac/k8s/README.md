# KUBAPP — Kubernetes Layer

The `k8s/` directory contains the Terraform configuration used to configure and bootstrap the Kubernetes layer of KUBAPP.
The AWS infrastructure is created first by [`iac/infra`](../infra/). This layer then connects to that infrastructure and prepares the EKS cluster for running applications and platform services.

## Purpose

This layer is responsible for turning the provisioned EKS cluster into a usable KUBAPP platform.

It configures:

* Kubernetes namespaces
* AWS Load Balancer Controller
* ExternalDNS
* Argo CD
* Fluent Bit logging
* Prometheus, Grafana, and Alertmanager
* EFS and EBS CSI storage
* Kubernetes service accounts and AWS workload identity
* Fargate logging
* Cluster readiness checks

## How It Relates to `infra/`

The two Terraform layers have different responsibilities:

```text"
iac/infra/
    │
    ▼
AWS infrastructure
    ├── VPC
    ├── Networking
    ├── Security
    ├── IAM / IRSA
    ├── EKS
    ├── EFS
    ├── ACM
    └── Logging
         │
         ▼
iac/k8s/
    │
    ▼
Kubernetes platform configuration
    ├── Namespaces
    ├── Storage
    ├── Load Balancing
    ├── DNS
    ├── GitOps
    ├── Logging
    └── Monitoring
```

The `k8s/` layer reads required outputs from the `infra/` Terraform state instead of recreating AWS resources.

This keeps AWS infrastructure and Kubernetes configuration separated while allowing them to work together.

## Platform Services

KUBAPP bootstraps the core services required to operate the cluster:

| Service                          | Purpose                                              |
| -------------------------------- | ---------------------------------------------------- |
| **Argo CD**                      | GitOps-based application deployment                  |
| **AWS Load Balancer Controller** | Creates AWS load balancers from Kubernetes resources |
| **ExternalDNS**                  | Manages DNS records from Kubernetes resources        |
| **Fluent Bit**                   | Collects and forwards Kubernetes logs                |
| **Prometheus**                   | Collects cluster and application metrics             |
| **Grafana**                      | Provides metrics dashboards                          |
| **Alertmanager**                 | Handles monitoring alerts                            |
| **EFS CSI**                      | Provides shared persistent storage                   |
| **EBS CSI**                      | Provides block storage for Kubernetes workloads      |

## Environment Support

The layer supports separate Kubernetes environments such as:

```text id="2fd6cm"
envs/
├── dev/
└── prod/
```

Each environment uses its own Terraform state and configuration while following the same platform structure.

## Design Goal

The goal of this layer is to make a newly provisioned EKS cluster **platform-ready**.
After `iac/infra/` creates the required AWS resources, `iac/k8s/` installs and configures the Kubernetes services needed for:

* Application deployment
* Networking
* DNS
* Persistent storage
* Observability
* GitOps operations

Application workloads can then be deployed through the KUBAPP application and GitOps workflows.
