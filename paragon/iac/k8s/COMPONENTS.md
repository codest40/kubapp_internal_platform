# KUBAPP — Kubernetes Layer Components

## 1. Layer Responsibility

The KUBAPP infrastructure is intentionally divided into two Terraform layers:
The separation prevents the Kubernetes layer from recreating or managing AWS infrastructure that belongs to iac/infra/.

```text
iac/infra/
        │
        │ Creates AWS infrastructure
        ▼
┌─────────────────────────────┐
│ VPC                         │
│ Subnets                     │
│ Security Groups             │
│ IAM / IRSA                  │
│ EKS                         │
│ EFS                         │
│ ACM                         │
│ CloudWatch                  │
└─────────────────────────────┘
        │
        │ Terraform remote state
        ▼
iac/k8s/
        │
        │ Configures Kubernetes
        ▼
┌─────────────────────────────┐
│ Namespaces                  │
│ CSI Drivers                 │
│ Load Balancer Controller    │
│ ExternalDNS                 │
│ Argo CD                     │
│ Fluent Bit                  │
│ Prometheus                  │
│ Grafana                     │
│ Alertmanager                │
└─────────────────────────────┘
```

The result is a Kubernetes cluster that is not merely provisioned, but **bootstrapped with the core services required to operate applications as a platform**.

## 2. Terraform Providers

The layer uses four Terraform providers:

| Provider   | Purpose                                            |
| ---------- | -------------------------------------------------- |
| AWS        | Interacts with AWS resources such as EKS add-ons   |
| Kubernetes | Creates and manages Kubernetes resources           |
| Helm       | Installs Kubernetes applications using Helm charts |
| Null       | Executes readiness and bootstrap commands          |

The providers are pinned in `versions.tf` to make deployments reproducible.

```text
AWS
 │
 ├── EKS
 └── EKS Add-ons

Kubernetes
 │
 ├── Namespaces
 ├── ServiceAccounts
 ├── ConfigMaps
 └── StorageClasses

Helm
 │
 ├── Argo CD
 ├── ExternalDNS
 ├── AWS Load Balancer Controller
 ├── Fluent Bit
 └── kube-prometheus-stack

Null
 │
 └── Readiness / bootstrap commands
```

## 3. Remote Terraform State

The Kubernetes layer maintains its own Terraform state:

```text
S3
└── kubapp-tf-state
    └── dev/
        └── k8s/
            └── terraform.tfstate
```

This is separate from the infrastructure state:

```text
dev/infra/terraform.tfstate
dev/k8s/terraform.tfstate
```

This separation allows the AWS infrastructure and Kubernetes configuration to have independent Terraform lifecycles.

For example:

```text
terraform apply infra
        │
        ▼
AWS infrastructure exists
        │
        ▼
terraform apply k8s
        │
        ▼
Kubernetes platform is configured
```

## 4. Consuming Infrastructure State

`local.tf` uses Terraform's `terraform_remote_state` data source to consume values produced by the infrastructure layer.

```hcl
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "kubapp-tf-state"
    key    = "${var.env}/infra/terraform.tfstate"
    region = var.region
  }
}
```

Examples of values consumed from the infrastructure layer include:

```text
VPC ID
EKS cluster name
EKS endpoint
EKS CA certificate
EFS ID
IRSA role ARNs
CloudWatch log groups
domain
```

This is important because `k8s/` does not need to duplicate these values.

For example:

```text
local.cluster_name
local.vpc_id
local.efs_id
local.lb_controller_role_arn
```

are derived from the infrastructure layer.

## 5. Kubernetes Provider

The Kubernetes provider connects Terraform to the EKS API:

```hcl
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_cert)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"

    args = [
      "eks",
      "get-token",
      "--cluster-name",
      local.cluster_name
    ]
  }
}
```

KUBAPP does not store a static Kubernetes authentication token.

Instead, Terraform uses the AWS CLI to obtain an EKS authentication token.

This keeps authentication tied to AWS IAM rather than storing Kubernetes credentials in the repository.

## 6. Helm Provider

The Helm provider uses the same EKS authentication mechanism.

This allows Terraform to install Helm-based platform services directly into the cluster.

The major Helm deployments are:

```text
AWS Load Balancer Controller
ExternalDNS
Argo CD
Fluent Bit
kube-prometheus-stack
```

Using Helm allows KUBAPP to manage these services declaratively while keeping their configuration inside Terraform.

## 7. Namespaces

`namespaces.tf` creates platform namespaces from a local map:

```text
argocd
monitoring
aws-observability
```

The namespace definitions also contain labels describing the workload.

For example:

```text
component
workload
environment
project
telemetry
```

The namespace structure separates platform responsibilities:

```text
argocd
    → GitOps

monitoring
    → Metrics and alerting

aws-observability
    → AWS / Fargate logging
```

Application namespaces can be added separately as the platform evolves.

## 8. Kubernetes Service Accounts and IRSA

`sa.tf` creates Kubernetes service accounts for AWS-integrated components.

Examples:

```text
aws-load-balancer-controller
external-dns
fluent-bit
```

Each service account is associated with an IAM role:

```hcl
"eks.amazonaws.com/role-arn" = local.lb_controller_role_arn
```

This uses EKS IAM Roles for Service Accounts (IRSA).

The model is:

```text
Kubernetes Pod
      │
      ▼
ServiceAccount
      │
      ▼
IRSA / OIDC
      │
      ▼
AWS IAM Role
      │
      ▼
AWS API
```

This avoids putting AWS access keys inside Kubernetes Secrets or application containers.

The IAM roles themselves are created by the `iac/infra/modules/iam-irsa` layer.

## 9. AWS Load Balancer Controller

The AWS Load Balancer Controller is installed using Helm.

Its purpose is to allow Kubernetes resources to create and manage AWS load balancers.

The general flow is:

```text
Kubernetes Ingress
        │
        ▼
AWS Load Balancer Controller
        │
        ▼
AWS ALB
        │
        ▼
Application Service
```

This allows application networking to remain Kubernetes-native while AWS provides the underlying load-balancing infrastructure.

The controller uses IRSA rather than static AWS credentials.

## 10. ExternalDNS

ExternalDNS automatically manages DNS records based on Kubernetes resources.

The flow is:

```text
Kubernetes Ingress
        │
        ▼
ExternalDNS
        │
        ▼
Route 53
```

For example, an application can expose:

```text
app.rundailytest.online
```

without requiring a separate manual DNS change for every deployment.

ExternalDNS is restricted to the configured domain using:

```text
domainFilters
```

This reduces the scope of DNS permissions.

## 11. Argo CD

Argo CD provides the GitOps deployment layer.

KUBAPP installs Argo CD using Helm.

The intended flow is:

```text
Git Repository
      │
      ▼
   Argo CD
      │
      ▼
Kubernetes Cluster
      │
      ▼
Applications
```

Argo CD continuously compares the desired state stored in Git with the state running in Kubernetes.

This moves application deployment away from manually executing:

```text
kubectl apply
```

and toward a declarative GitOps workflow.

The Argo CD configuration also defines separate permissions for automation and administrative access.

## 12. Fluent Bit

Fluent Bit collects Kubernetes container logs.

It runs as a DaemonSet on Linux EC2 nodes.

The general pipeline is:

```text
Container
    │
    ▼
/var/log/containers
    │
    ▼
Fluent Bit
    │
    ▼
CloudWatch Logs
```

Fluent Bit enriches logs with Kubernetes metadata such as:

```text
namespace
pod
container
node
application
cluster
environment
```

This makes logs easier to search and correlate during troubleshooting.

Fargate workloads use the AWS-supported logging configuration separately through `fargate_log.tf`.

## 13. Fargate Logging

Fargate workloads do not have the same host-level log access available on EC2 nodes.

Therefore, KUBAPP configures the special AWS logging mechanism through the:

```text
aws-logging
```

ConfigMap in the:

```text
aws-observability
```

namespace.

The flow becomes:

```text
Fargate Pod
    │
    ▼
AWS Fargate Logging
    │
    ▼
CloudWatch Logs
```

This allows both EC2-backed and Fargate workloads to have centralized logging.

## 14. Prometheus

KUBAPP installs the `kube-prometheus-stack`.

Prometheus provides metrics collection for the Kubernetes platform and workloads.

The stack includes components such as:

```text
Prometheus
Node Exporter
Alertmanager
Grafana
```

Prometheus collects metrics from Kubernetes and applications that expose Prometheus-compatible metrics.

Examples include:

```text
CPU usage
Memory usage
Node health
Pod health
Application metrics
Kubernetes control-plane metrics
```

## 15. Node Exporter

Node Exporter runs on EC2-backed Kubernetes nodes.

It exposes operating-system-level metrics to Prometheus.

Examples:

```text
CPU
Memory
Disk
Filesystem
Network
Load
```

Fargate nodes are excluded because Fargate does not expose the same underlying host environment.

## 16. Grafana

Grafana provides the visualization layer for Prometheus metrics.

The architecture is:

```text
Kubernetes / Applications
          │
          ▼
      Prometheus
          │
          ▼
        Grafana
```

Grafana persistence is backed by the EFS storage class.

This allows Grafana configuration and state to survive pod recreation.

## 17. Alertmanager

Alertmanager handles alerts generated by Prometheus.

The flow is:

```text
Prometheus
    │
    │ Alert
    ▼
Alertmanager
    │
    ▼
Notification
```

KUBAPP currently configures email notifications.

Alertmanager also provides alert grouping and repeat intervals to prevent excessive notification noise.

## 18. Persistent Storage

KUBAPP uses both EFS and EBS.

```text
EFS
└── Shared / ReadWriteMany storage

EBS
└── Block storage / ReadWriteOnce workloads
```

These are exposed to Kubernetes through CSI drivers.

## 19. EFS CSI Driver

The AWS EFS CSI driver allows Kubernetes workloads to use the EFS filesystem created by the infrastructure layer.

KUBAPP creates an EFS StorageClass:

```text
efs-sc
```

The flow is:

```text
Pod
 │
 ▼
PVC
 │
 ▼
efs-sc
 │
 ▼
EFS CSI Driver
 │
 ▼
AWS EFS
```

EFS is useful where multiple pods need access to shared storage.

The StorageClass uses EFS Access Points for dynamic provisioning.

## 20. EBS CSI Driver

The AWS EBS CSI driver provides block storage for Kubernetes.

KUBAPP creates a:

```text
gp3
```

StorageClass.

The flow is:

```text
Pod
 │
 ▼
PVC
 │
 ▼
gp3 StorageClass
 │
 ▼
EBS CSI Driver
 │
 ▼
AWS EBS
```

EBS is appropriate for workloads that require block storage and typically use `ReadWriteOnce`.

Prometheus uses this storage for its metrics data.

## 21. Why Both EFS and EBS?

They solve different storage problems.

| Storage | Best suited for                        |
| ------- | -------------------------------------- |
| EFS     | Shared filesystem access               |
| EBS     | Block storage for individual workloads |

For example:

```text
Grafana
    → EFS

Prometheus
    → EBS gp3
```

This allows each workload to use storage appropriate to its access pattern.

## 22. Cluster Readiness

`readiness.tf` handles dependencies that cannot always be represented purely through Terraform resource creation.

For example:

```text
EKS created
    │
    ▼
Wait for cluster to become active
    │
    ▼
EFS CSI ready
    │
    ▼
Load Balancer Controller ready
    │
    ▼
Argo CD / Monitoring ready
    │
    ▼
Cluster marked READY
```

Terraform's `depends_on` controls resource ordering, while `kubectl` and AWS CLI readiness checks verify that services are actually operational.

A readiness ConfigMap is used to expose the platform state:

```text
status = initializing
```

and eventually:

```text
status = ready
```

This provides a simple signal that the bootstrap process has completed.

## 23. Local Configuration and Labels

`local.tf` also centralizes common metadata.

KUBAPP applies consistent labels such as:

```text
project
environment
cluster
component
workload
plane
runtime
telemetry
```

This allows resources to be identified consistently across:

```text
Kubernetes
CloudWatch
AWS
Prometheus
Logs
```

For example:

```text
plane = k8s
component = monitoring
telemetry = metrics
```

This becomes useful when filtering resources or troubleshooting the platform.

## 24. Environment Configuration

Environment-specific values are kept under:

```text
envs/
├── dev/
│   ├── backend.hcl
│   └── k8s.tfvars
└── prod/
    └── backend.hcl
```

The same Terraform configuration can therefore be used for multiple environments.

The environment determines values such as:

```text
cluster identity
domain
region
alert configuration
Terraform state location
```

The goal is to avoid creating separate Terraform codebases for development and production.

## 25. Secrets

Sensitive values such as alerting credentials are not stored as plaintext Terraform variables in the repository.

The intended workflow is:

```text
Encrypted configuration
        │
        ▼
Authorized deployment workflow
        │
        ▼
Terraform
        │
        ▼
Kubernetes / AWS
```

SOPS/age is used in the KUBAPP configuration in root to protect sensitive environment configuration.

## 26. Dependency Order

The major dependency chain is:

```text
iac/infra
    │
    ├── VPC
    ├── IAM / IRSA
    ├── EKS
    ├── EFS
    └── Logging
         │
         ▼
     iac/k8s
         │
         ├── Kubernetes connection
         ├── Namespaces
         ├── Service Accounts
         ├── CSI Drivers
         ├── Load Balancer Controller
         ├── ExternalDNS
         ├── Fluent Bit
         ├── Argo CD
         └── Monitoring Stack
```

The explicit dependencies and readiness checks reduce failures caused by attempting to configure Kubernetes components before the EKS control plane or required AWS integrations are ready.

## 27. Why Terraform Manages These Components

KUBAPP uses Terraform for this bootstrap layer because the platform itself should be reproducible.
Instead of manually installing:

```text
helm install ...
kubectl apply ...
```

the platform can be recreated from code.

This provides:

* Reproducibility
* Version control
* Environment consistency
* Dependency management
* Automated provisioning
* Easier recovery

Terraform is primarily responsible for **platform bootstrap** here.
Argo CD then becomes responsible for **ongoing application GitOps deployment**.

## 28. Platform vs Application Responsibility

A key design boundary in KUBAPP is:

```text
Terraform
    │
    └── Platform foundation
         ├── EKS
         ├── Networking
         ├── Storage integration
         ├── IAM
         ├── Logging
         ├── Monitoring
         └── Platform controllers

Argo CD
    │
    └── Application workloads
         ├── Services
         ├── Deployments
         ├── Ingress
         ├── Configuration
         └── Application lifecycle
```

This prevents Terraform from becoming the primary application deployment mechanism.

## 29. Overall Technical Flow

The complete KUBAPP flow is:

```text
Terraform Boot
     │
     ▼
S3 + Terraform State Locking
     │
     ▼
Terraform Infrastructure
     │
     ├── VPC
     ├── IAM
     ├── EKS
     ├── EFS
     ├── ACM
     └── CloudWatch
     │
     ▼
Terraform Kubernetes Layer
     │
     ├── Kubernetes namespaces
     ├── CSI drivers
     ├── AWS Load Balancer Controller
     ├── ExternalDNS
     ├── Fluent Bit
     ├── Argo CD
     └── Prometheus / Grafana / Alertmanager
     │
     ▼
GitOps Application Layer
     │
     ▼
KUBAPP Applications
```

## Summary

The `k8s/` layer is the **Kubernetes platform bootstrap layer** of KUBAPP.
It takes the AWS infrastructure created by `iac/infra/` and turns the EKS cluster into a platform-ready environment with networking, DNS, storage, logging, monitoring, and GitOps capabilities.
Application workloads are then managed through the GitOps application layer.
