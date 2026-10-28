# KUBAPP — Kubernetes Components

## 1. Layer Responsibility

`iac/k8s` is the Kubernetes platform/bootstrap layer of KUBAPP.

It configures the Kubernetes resources and platform services required after the AWS infrastructure has been provisioned.

The layer is responsible for:

* Kubernetes namespaces
* Kubernetes and Helm providers
* Platform service accounts and IRSA
* VPC CNI configuration
* Security Groups for Pods
* AWS Load Balancer Controller
* ExternalDNS
* Argo CD
* Fluent Bit
* Fargate logging
* Prometheus
* Grafana
* Alertmanager
* EFS CSI
* EBS CSI
* StorageClasses
* Cluster readiness checks
* Application/platform secrets

The AWS infrastructure itself is created by `iac/infra`.

---

## 2. Providers

The layer uses four Terraform providers:

* AWS
* Kubernetes
* Helm
* Null

### AWS

Used for EKS add-ons and reading infrastructure information.

### Kubernetes

Used to create Kubernetes-native resources such as:

* Namespaces
* Service Accounts
* ConfigMaps
* StorageClasses
* SecurityGroupPolicy resources

### Helm

Used to install and configure platform components:

* AWS Load Balancer Controller
* ExternalDNS
* Argo CD
* Fluent Bit
* kube-prometheus-stack

### Null

Used for local execution steps involved in cluster readiness and secret application.

---

## 3. Terraform State

The Kubernetes layer has its own Terraform state.

The backend is configured for the environment-specific Kubernetes state, while the exact backend values are supplied through the environment configuration.

The Kubernetes layer is therefore managed independently from the AWS infrastructure state.

---

## 4. Consuming Infrastructure State

The Kubernetes layer reads outputs from the `iac/infra` Terraform state through `terraform_remote_state`.

It consumes infrastructure information such as:

* VPC ID
* EKS cluster name
* EKS endpoint
* EKS CA certificate
* AWS IAM role ARNs
* EFS ID
* CloudWatch log groups
* Application Security Group IDs
* EKS cluster Security Group ID
* Workload configuration

The Kubernetes layer does not recreate these AWS resources. It consumes the outputs produced by the infrastructure layer.

---

## 5. Kubernetes Authentication

The Kubernetes provider connects directly to the EKS API endpoint.

Authentication uses the AWS CLI:

```text
aws eks get-token
```

The Helm provider uses the same EKS authentication mechanism.

No static Kubernetes authentication token is stored in Terraform configuration.

---

## 6. Namespaces

KUBAPP creates four namespace categories:

### Environment namespace

The active environment namespace is created dynamically from:

```text
var.env
```

For example:

```text
dev
```

This is the application namespace.

### Argo CD

```text
argocd
```

Used for GitOps control.

### Monitoring

```text
monitoring
```

Used for metrics, Grafana, Prometheus, and Alertmanager.

### AWS Observability

```text
aws-observability
```

Used for AWS/Fargate logging configuration.

Namespace labels are generated centrally from the KUBAPP Kubernetes labels and the namespace's component/workload classification.

---

## 7. Service Accounts and IRSA

KUBAPP creates dedicated Kubernetes service accounts for AWS-integrated platform components.

### AWS Load Balancer Controller

```text
aws-load-balancer-controller
```

Uses the IAM role supplied by the infrastructure layer.

### ExternalDNS

```text
external-dns
```

Uses its own IAM role supplied by the infrastructure layer.

### Fluent Bit

```text
fluent-bit
```

Uses its own IAM role supplied by the infrastructure layer.

These service accounts use IAM Roles for Service Accounts (IRSA), allowing Kubernetes workloads to access AWS APIs without embedding AWS credentials in Pods.

---

## 8. VPC CNI and Pod Networking

KUBAPP manages the Amazon VPC CNI as an EKS add-on.

The add-on is selected according to the current EKS Kubernetes version.

The configuration explicitly enables:

```text
ENABLE_POD_ENI=true
```

This enables the networking required for assigning AWS Security Groups directly to Pods.

This is the foundation for KUBAPP's Security Groups for Pods configuration.

---

## 9. Security Groups for Pods

KUBAPP separates AWS-level workload security from Kubernetes workload placement.

The Security Groups themselves are created by the infrastructure layer.

The Kubernetes layer consumes their IDs and applies them to Pods using the AWS VPC CNI `SecurityGroupPolicy` resource.

The policies select Pods using **Pod labels**, not node labels.

---

## 10. EC2 Application Pod Security

EC2-backed application Pods are selected using:

```text
compute=ec2
```

The matching Pods receive the:

```text
ec2_app
```

Security Group.

The EC2 worker nodes themselves retain their EKS/node-level Security Groups.

The `ec2_app` Security Group is therefore a workload-level security boundary for application Pods, not a replacement for the node Security Group.

---

## 11. Fargate Application Pod Security

Fargate application Pods are selected using:

```text
compute=fargate
```

The matching Pods receive two Security Groups:

* `fargate_app`
* EKS cluster Security Group

The cluster Security Group is included alongside the workload Security Group so that the Fargate Pods retain the required connectivity to the EKS control plane while using the custom workload Security Group.

---

## 12. AWS Load Balancer Controller

The AWS Load Balancer Controller is installed through Helm in:

```text
kube-system
```

It manages AWS load-balancing resources for Kubernetes workloads.

KUBAPP configures it with:

* EKS cluster name
* AWS region
* VPC ID
* Existing IAM-backed service account

The controller is configured to install its required CRDs.

KUBAPP uses the controller for its ALB-based application ingress architecture.

---

## 13. ExternalDNS

ExternalDNS is installed in:

```text
kube-system
```

It integrates Kubernetes ingress resources with AWS DNS.

KUBAPP configures:

* AWS as the DNS provider
* Ingress as the source
* A domain filter for the KUBAPP domain
* TXT ownership records
* `upsert-only` policy

This allows Kubernetes ingress changes to create/update the required DNS records without allowing ExternalDNS to delete unrelated records.

---

## 14. Argo CD

Argo CD is installed in:

```text
argocd
```

using the Argo CD Helm chart.

KUBAPP configures Argo CD for GitOps application deployment.

The Argo CD server runs as a ClusterIP service and is intended to be exposed through the KUBAPP ingress/TLS architecture.

KUBAPP also configures automation and administrative Argo CD accounts/RBAC.

Terraform establishes the Argo CD platform component; Argo CD is then responsible for ongoing application GitOps reconciliation.

---

## 15. Fluent Bit

Fluent Bit runs as a DaemonSet on Linux EC2 nodes.

It:

* Reads container logs from `/var/log/containers`
* Parses CRI-formatted logs
* Enriches records with Kubernetes metadata
* Adds KUBAPP cluster/environment information
* Sends application logs to CloudWatch Logs

The DaemonSet explicitly excludes Fargate nodes because Fargate uses its own logging mechanism.

---

## 16. Fargate Logging

Fargate logging is configured through the AWS-supported `aws-logging` ConfigMap in:

```text
aws-observability
```

The configuration sends Fargate container logs to the designated CloudWatch log group.

The current configuration uses:

```text
auto_create_group false
```

Therefore the expected CloudWatch log group is provisioned outside this ConfigMap rather than being automatically created by the Fargate logging configuration.

Fargate logging and EC2-node Fluent Bit are therefore separate paths into CloudWatch.

---

## 17. Prometheus

KUBAPP deploys the `kube-prometheus-stack` Helm chart in:

```text
monitoring
```

Prometheus provides Kubernetes and application metrics collection.

The current configuration uses:

* 7-day retention
* 15 GB retention-size limit
* Persistent storage
* EBS `gp3`
* 20 GiB volume
* Linux node placement

Prometheus is part of the platform observability layer.

---

## 18. Node Exporter

Node Exporter is deployed as part of the Prometheus stack.

It provides node-level metrics for the Linux EC2 workers.

Fargate is excluded because Fargate does not expose a normal node environment for Node Exporter to monitor.

---

## 19. Grafana

Grafana is deployed as part of the Prometheus stack.

It provides the visualization layer for platform metrics.

KUBAPP configures:

* ClusterIP service
* Anonymous access disabled
* Existing admin secret
* Persistent storage
* EFS-backed storage
* `efs-sc` StorageClass
* 10 GiB capacity
* ReadWriteMany access

Grafana therefore keeps its persistent data outside the Pod filesystem.

---

## 20. Alertmanager

Alertmanager is enabled as part of the Prometheus stack.

The current configuration includes:

* 120-hour retention
* Persistent storage
* EFS-backed storage
* 5 GiB capacity
* Alert grouping by `alertname`
* 30-second group wait
* 5-minute group interval
* 1-hour repeat interval

Email notifications are configured through SMTP.

Resolved notifications are also enabled.

---

## 21. Persistent Storage

KUBAPP uses both EFS and EBS through their AWS EKS CSI add-ons.

They serve different workload requirements.

### EFS

Used where shared or filesystem-oriented persistence is appropriate.

### EBS

Used where block storage is appropriate, such as Prometheus.

---

## 22. EFS CSI

KUBAPP manages the AWS EFS CSI driver as an EKS add-on.

The EFS StorageClass is:

```text
efs-sc
```

It uses:

```text
efs.csi.aws.com
```

with dynamic provisioning through EFS Access Points:

```text
provisioningMode = efs-ap
```

The StorageClass uses:

* EFS filesystem supplied by infrastructure
* Dynamic provisioning base path `/dynamic_provisioning`
* `Retain` reclaim policy
* Immediate binding
* Volume expansion enabled

The EFS IAM role is supplied by the infrastructure layer.

---

## 23. EBS CSI

KUBAPP also manages the AWS EBS CSI driver as an EKS add-on.

The StorageClass is:

```text
gp3
```

It uses:

```text
ebs.csi.aws.com
```

with:

* `gp3`
* `ext4`
* `WaitForFirstConsumer`
* Volume expansion enabled
* Not configured as the default StorageClass

The EBS CSI IAM role is supplied by the infrastructure layer.

Prometheus uses this StorageClass for its persistent volume.

---

## 24. Cluster Readiness

KUBAPP does not treat EKS creation as the end of cluster provisioning.

The Kubernetes layer performs readiness checks using AWS CLI, `kubectl`, and Terraform `null_resource` local-exec steps.

The checks include:

* Waiting for the EKS cluster to become active
* Waiting for the EFS CSI controller and node components
* Waiting for the AWS Load Balancer Controller deployment
* Waiting for the Load Balancer Controller webhook endpoints
* Waiting for Argo CD and monitoring components

KUBAPP also creates a `cluster-readiness` ConfigMap in `kube-system`.

The readiness state starts as:

```text
initializing
```

and is changed to:

```text
ready
```

after the required platform components are available.

This provides an explicit Kubernetes-level readiness signal for the completed bootstrap process.

---

## 25. Central Configuration and Labels

Common configuration is centralized in `local.tf`.

This includes:

* Cluster information
* AWS resource IDs
* IAM role ARNs
* EFS information
* CloudWatch log groups
* Workload selectors
* Environment
* Domain
* Common Kubernetes labels

Labels identify information such as:

```text
cluster_name
resource-type
env
project
plane
runtime
trace-id
```

Monitoring and logging components extend the common labels with their own component and telemetry information.

---

## 26. Environment Configuration

The Kubernetes layer accepts an environment variable through:

```text
var.env
```

Supported values are:

```text
dev
staging
prod
```

Environment-specific Terraform values are maintained under:

```text
envs/
```

The environment determines the active application namespace and the corresponding infrastructure state consumed by the Kubernetes layer.

---

## 27. Secrets

KUBAPP keeps application/platform secret configuration separate from ordinary Kubernetes resource definitions.

The Kubernetes layer invokes:

```text
scripts/gitops/apply_secrets.py
```

to apply the secret configuration from:

```text
gitops/secrets
```

Terraform tracks changes to the secret files and reruns the application step when those files change.

Encrypted secret configuration is maintained through the KUBAPP secrets workflow rather than storing ordinary secret values directly in Kubernetes Terraform resources.

---

## 28. Dependency and Bootstrap Model

The Kubernetes layer has dependencies between infrastructure, AWS add-ons, Kubernetes resources, and Helm components.

The general model is:

```text
AWS Infrastructure
        │
        ▼
Terraform Remote State
        │
        ▼
EKS Authentication
        │
        ├── VPC CNI / Pod ENI
        ├── EFS CSI
        └── EBS CSI
        │
        ▼
Namespaces + Service Accounts
        │
        ├── SecurityGroupPolicy
        ├── StorageClasses
        └── Platform configuration
        │
        ▼
Helm Platform Components
        │
        ├── AWS Load Balancer Controller
        ├── ExternalDNS
        ├── Argo CD
        ├── Fluent Bit
        └── kube-prometheus-stack
        │
        ▼
Readiness Checks
        │
        ▼
Cluster Ready
        │
        ▼
Argo CD GitOps
        │
        ▼
Applications
```

Terraform establishes the platform foundation. Argo CD then handles ongoing application reconciliation.

---

## 29. Platform vs Application Responsibility

KUBAPP separates platform provisioning from application deployment.

### Terraform / `iac/k8s`

Responsible for:

* Kubernetes platform configuration
* Namespaces
* AWS integrations
* Networking configuration
* SecurityGroupPolicy
* Storage
* Logging
* Monitoring
* Argo CD
* Cluster readiness

### Argo CD

Responsible for:

* Application GitOps
* Application manifests
* Application deployment
* Continuous reconciliation

This keeps the Kubernetes platform bootstrap separate from the application's ongoing deployment lifecycle.

---

## 30. Overall Technical Flow

The current KUBAPP Kubernetes flow is:

```text
iac/infra
   │
   │ AWS infrastructure + IAM + networking
   ▼
Terraform Remote State
   │
   ▼
iac/k8s
   │
   ├── EKS authentication
   ├── VPC CNI + Pod ENI
   ├── namespaces
   ├── service accounts / IRSA
   ├── Pod Security Groups
   ├── CSI drivers + StorageClasses
   ├── AWS Load Balancer Controller
   ├── ExternalDNS
   ├── Fluent Bit
   ├── Fargate logging
   ├── Prometheus / Grafana / Alertmanager
   └── Argo CD
   │
   ▼
Cluster readiness = ready
   │
   ▼
Argo CD
   │
   ▼
KUBAPP applications
```

The Kubernetes layer therefore establishes the **operational platform** on which KUBAPP applications run.

---

## Summary

`iac/k8s` is the Kubernetes platform layer of KUBAPP.

It consumes AWS infrastructure outputs rather than recreating the infrastructure, configures EKS networking and Pod-level Security Groups, establishes persistent storage, installs the platform's ingress, DNS, logging, monitoring, and GitOps components, and verifies that the resulting cluster is operational.

The resulting separation is:

```text
iac/infra
    ↓
AWS foundation
    ↓
iac/k8s
    ↓
Kubernetes platform
    ↓
Argo CD
    ↓
Applications
```

