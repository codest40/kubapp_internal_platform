# KUBAPP — Infrastructure Components

## 1. Layer Responsibility

`iac/infra` is the AWS infrastructure layer of KUBAPP.

It provisions the AWS resources required to run the KUBAPP Kubernetes platform.

Unlike `iac/k8s`, which manages Kubernetes resources and platform services, `iac/infra` is organized into Terraform modules.

Each module represents an infrastructure component with a defined responsibility.

The current components are:

```text
network
sg-prep
security
iam-core
eks
iam-irsa
logging
efs
acm
```

The infrastructure layer also consumes DNS information from a separate Terraform state.

---

## 2. Infrastructure Component Model

The high-level infrastructure structure is:

```text
iac/infra
│
├── network
│   └── VPC, subnets, routing, NAT, VPC Flow Logs
│
├── sg-prep
│   └── Security Group definitions
│
├── security
│   └── Workload Security Groups and rules
│
├── iam-core
│   └── Core AWS IAM roles
│
├── eks
│   └── EKS cluster, EC2 nodes, Fargate, OIDC, access
│
├── iam-irsa
│   └── IAM roles for Kubernetes workloads
│
├── logging
│   └── CloudWatch log groups
│
├── efs
│   └── EFS filesystem, mount targets, storage SG
│
└── acm
    └── ACM certificate and DNS validation
```

Terraform determines the actual dependency graph from resource references and explicit `depends_on` relationships rather than from the order of blocks in `main.tf`.

---

# 3. Network

Module:

```text
modules/network
```

The network module creates the VPC foundation for KUBAPP.

### VPC

The module creates a VPC with:

```text
10.0.0.0/16
```

DNS support and DNS hostnames are enabled.

### Availability Zones

The current configuration uses:

```text
us-east-1a
us-east-1b
```

### Public subnets

```text
10.0.1.0/24
10.0.2.0/24
```

Public subnets:

* map public IPs on launch
* route through the Internet Gateway
* are tagged for EKS external load balancers

### Private subnets

```text
10.0.11.0/24
10.0.12.0/24
```

Private subnets:

* do not receive public IPs by default
* route outbound traffic through NAT
* are tagged for EKS internal load balancers

EKS worker nodes and Fargate workloads use the private subnets.

### Internet Gateway

The module creates an Internet Gateway for public subnet connectivity.

### NAT Gateways

A NAT Gateway is created per configured Availability Zone.

Each NAT Gateway receives its own Elastic IP.

Private subnet route tables send default traffic through the NAT Gateway in their corresponding AZ.

This provides AZ-local outbound routing for private workloads.

### Route Tables

The module creates:

* one public route table
* one private route table per AZ

Public traffic:

```text
Public subnet
    ↓
Internet Gateway
    ↓
Internet
```

Private outbound traffic:

```text
Private subnet
    ↓
NAT Gateway
    ↓
Internet Gateway
    ↓
Internet
```

### VPC Flow Logs

The network module also creates VPC Flow Logs.

Traffic type is:

```text
ALL
```

Logs are delivered to CloudWatch Logs using a dedicated IAM role.

---

# 4. Security Group Preparation

Module:

```text
modules/sg-prep
```

`sg-prep` does not create AWS Security Groups.

It creates the **Security Group definitions** consumed by the `security` module.

The current definitions include:

### `ingress`

The external entry-point Security Group.

Allows:

```text
TCP 80
TCP 443
```

from:

```text
0.0.0.0/0
```

### `ec2_app`

Defines the workload Security Group for EC2-backed application Pods.

Current application port:

```text
TCP 3000
```

Ingress is allowed from:

```text
ingress
```

### `fargate_app`

Defines the workload Security Group for Fargate application Pods.

Current application port:

```text
TCP 4000
```

Ingress is allowed from:

```text
ingress
```

### `db_access`

Defines the Security Group for the cache service.

Current port:

```text
TCP 6379
```

Ingress is allowed from:

```text
ec2_app
fargate_app
```

The module also supports additional/custom Security Group definitions.

The separation is intentional:

```text
sg-prep
    │
    │ definitions
    ▼
security
    │
    │ AWS Security Groups
    ▼
KUBAPP networking
```

---

# 5. Security

Module:

```text
modules/security
```

The security module turns the definitions produced by `sg-prep` into actual AWS Security Groups.

It creates one Security Group for every entry in `sg_definitions`.

It supports both:

* Security Group-based rules
* CIDR-based rules

Ingress and egress rules are expanded dynamically from the supplied definitions.

This makes the module reusable without hardcoding individual Security Groups into the module itself.

The module currently provides workload-oriented groups such as:

```text
ingress
ec2_app
fargate_app
db_access
```

The resulting Security Group IDs are exported as a map.

The Kubernetes layer consumes the relevant IDs for Pod-level SecurityGroupPolicy configuration.

---

# 6. Core IAM

Module:

```text
modules/iam-core
```

`iam-core` creates foundational AWS IAM roles used by EKS and supporting infrastructure.

It currently manages four main role areas.

## EKS Cluster Role

Trusted by:

```text
eks.amazonaws.com
```

Attached policies include:

* `AmazonEKSClusterPolicy`
* `AmazonEKSVPCResourceController`

The role is supplied to the EKS control plane.

## EC2 Node Group Role

Trusted by EC2.

Attached policies include:

* `AmazonEKSWorkerNodePolicy`
* `AmazonEKS_CNI_Policy`
* `AmazonEC2ContainerRegistryReadOnly`

This role is used by the EKS EC2 node groups.

## Fargate Pod Execution Role

Trusted by:

```text
eks-fargate-pods.amazonaws.com
```

Attached policies include:

* `AmazonEKSFargatePodExecutionRolePolicy`
* KUBAPP's scoped CloudWatch Logs policy

The custom CloudWatch policy allows Fargate workloads to:

```text
logs:CreateLogStream
logs:PutLogEvents
```

against the configured Fargate log group.

## System Monitor EC2 Role

The module also provisions an EC2 role for the KUBAPP system-monitor component.

It provides:

* EKS API access
* STS identity access
* Systems Manager access
* CloudWatch Agent access

An EC2 instance profile is created for this role.

The module also creates a cross-account role used by the system-monitor workflow.

That cross-account role currently provides access related to:

* EKS
* Terraform state S3
* Route53 read operations

---

# 7. EKS

Module:

```text
modules/eks
```

This is the core Kubernetes compute component.

It creates and configures:

* EKS control plane
* OIDC provider
* system EC2 node group
* application EC2 node group
* Fargate profile
* EKS access entries and policies

---

## 7.1 EKS Cluster

The cluster uses the Kubernetes version supplied through:

```text
var.kubernetes_v
```

The current default is:

```text
1.31
```

The cluster uses the private subnets.

Both EKS API endpoint modes are enabled:

```text
endpoint_private_access = true
endpoint_public_access  = true
```

The cluster authentication mode is:

```text
API_AND_CONFIG_MAP
```

EKS control-plane logging is enabled for:

* API
* Audit
* Authenticator
* Controller Manager
* Scheduler

---

## 7.2 EKS OIDC Provider

The module obtains the cluster's OIDC issuer certificate and creates an AWS IAM OIDC provider.

This establishes the identity foundation used by `iam-irsa`.

The relationship is:

```text
EKS
 │
 └── OIDC provider
        │
        ▼
     iam-irsa
        │
        ▼
 Kubernetes service accounts
```

---

## 7.3 System EC2 Nodes

The system node group is used for Kubernetes/system workloads.

Current configuration:

```text
instance type: t3.large
desired:       2
min:            1
max:            2
disk:          30 GiB
AMI:           AL2023 x86_64
```

Nodes are labeled:

```text
node_type=system
compute=system
```

These nodes are separate from the application EC2 node group.

---

## 7.4 Application EC2 Nodes

The application node group provides EC2 compute for application workloads.

Current configuration:

```text
instance type: t3.large
desired:       2
min:            1
max:            3
disk:          30 GiB
AMI:           AL2023 x86_64
```

Nodes are labeled:

```text
node_type=ec2
compute=ec2
```

The group also has:

```text
compute=ec2:NoSchedule
```

as a taint.

This allows the Kubernetes layer to explicitly control which workloads are scheduled onto the application EC2 nodes.

---

## 7.5 Fargate

The EKS module creates a Fargate profile for the configured application workload.

The profile selects Pods using:

```text
namespace = var.fargate_workloads.env
compute   = var.fargate_workloads.compute
```

The current workload model resolves to the environment namespace with:

```text
compute=fargate
```

Therefore Fargate scheduling is based on both:

* namespace
* Pod label

This allows Fargate workloads to coexist with EC2-backed application workloads in the platform.

---

# 8. EKS Access

The EKS module configures access using EKS Access Entries.

Three access paths are currently defined.

### Administrative access

`var.access_iam_arn` receives:

```text
AmazonEKSClusterAdminPolicy
```

with cluster-wide scope.

### Laptop/admin access

`var.admin_arn` receives the same cluster-wide administrator policy.

### System Monitor access

The system-monitor cross-account role receives:

```text
AmazonEKSViewPolicy
```

with cluster-wide scope.

This provides read-oriented EKS access for the monitoring workflow without granting it cluster-admin access.

---

# 9. IAM for Kubernetes Workloads

Module:

```text
modules/iam-irsa
```

This module creates IAM roles intended for Kubernetes service accounts through the EKS OIDC provider.

It separates AWS permissions for individual platform/workload components.

---

## 9.1 Application Pods

The module creates an application Pod role with read-only access to:

* CloudWatch metrics
* CloudWatch Logs
* S3

The trust policy uses the EKS OIDC provider and restricts the Kubernetes service-account subject to the configured application namespaces.

---

## 9.2 AWS Load Balancer Controller

A dedicated IRSA role is created for:

```text
system:serviceaccount:kube-system:aws-load-balancer-controller
```

The controller's IAM policy is loaded from:

```text
modules/iam-irsa/policies/iam_policy.json
```

This keeps the controller's AWS permissions separate from other platform components.

---

## 9.3 ExternalDNS

ExternalDNS receives its own IAM role.

Its permissions include:

* changing records in the configured Route53 hosted zone
* listing hosted zones
* listing resource record sets

The trust policy is restricted to:

```text
kube-system/external-dns
```

---

## 9.4 EBS CSI

The EBS CSI controller receives a dedicated IRSA role with:

```text
AmazonEBSCSIDriverPolicy
```

The role is associated with:

```text
kube-system/ebs-csi-controller-sa
```

The EKS add-on itself is managed by the Kubernetes layer rather than by this IAM module.

---

## 9.5 EFS CSI

The EFS CSI driver receives a dedicated IRSA role with:

```text
AmazonEFSCSIDriverPolicy
```

The trust policy covers EFS CSI service accounts in:

```text
kube-system
```

The EFS CSI add-on itself is managed by the Kubernetes layer.

---

## 9.6 Fluent Bit

Fluent Bit receives a dedicated IRSA role and CloudWatch policy.

Its permissions include:

* create log streams
* put log events
* create log groups
* describe log streams

This role is used by the Fluent Bit service account in the Kubernetes layer.

---

# 10. CloudWatch Logging

Module:

```text
modules/logging
```

The logging module creates CloudWatch Log Groups from a configurable map.

Each log group has:

* name
* retention
* log type
* scope

The current infrastructure configuration provisions log groups for:

```text
app_logs
audit_logs
fargate_logs
eks_cluster_log_group
vpc_flow_log
```

The exact retention period is supplied through the environment configuration.

The module exports both:

* log group names
* log group ARNs

These outputs are consumed by other infrastructure components and by `iac/k8s`.

Examples:

```text
network
   └── vpc_flow_log ARN

iam-core
   └── fargate_logs ARN

iac/k8s
   ├── app_logs
   └── fargate_logs
```

---

# 11. EFS

Module:

```text
modules/efs
```

The EFS module provides shared persistent storage for the platform.

It creates:

* EFS filesystem
* EFS mount targets
* dedicated EFS Security Group

---

## 11.1 EFS Security Group

The EFS Security Group allows NFS:

```text
TCP 2049
```

from the VPC CIDR.

Egress is also limited to the VPC CIDR.

This Security Group is separate from the workload Security Groups created by the `security` module.

---

## 11.2 EFS Filesystem

The filesystem is:

* encrypted
* associated with the KUBAPP cluster
* configured as shared persistent storage

---

## 11.3 Mount Targets

An EFS mount target is created for each supplied private subnet.

Therefore the filesystem is reachable from the private subnet topology used by the EKS workloads.

---

## 11.4 Access Points

The module contains commented-out access-point configuration.

The current active implementation creates the EFS filesystem and mount targets; dynamic EFS Access Point provisioning is handled later by the EFS CSI StorageClass in `iac/k8s`.

---

# 12. ACM

Module:

```text
modules/acm
```

The ACM component provisions the TLS certificate used by the KUBAPP domain.

It creates:

* ACM certificate
* DNS validation records
* ACM certificate validation

The certificate covers:

```text
var.domain
```

and:

```text
*.var.domain
```

DNS validation records are created in the supplied Route53 hosted zone.

The certificate uses:

```text
create_before_destroy = true
```

to avoid unnecessary certificate replacement gaps.

The validated certificate ARN is exported for consumption by the Kubernetes layer.

---

# 13. DNS State Dependency

The infrastructure layer does not create its primary DNS zone in this Terraform configuration.

Instead, it reads DNS information from a separate Terraform state:

```text
kubapp-dns-tf-state-${var.account_id}
```

The state provides:

* domain information
* Route53 hosted-zone ID

These values are consumed by:

```text
ACM
```

and:

```text
iam-irsa / ExternalDNS
```

The relationship is:

```text
DNS Terraform state
        │
        ├── domain
        └── hosted zone ID
                │
                ▼
             iac/infra
                │
                ├── ACM
                └── ExternalDNS IAM
```

---

# 14. Environment Configuration

The infrastructure layer supports:

```text
dev
staging
prod
```

The environment becomes part of the resource naming model.

For example:

```text
${project}-${env}
```

is used as the primary name prefix.

The EKS cluster name is similarly constructed from:

```text
${cluster_name}-${env}
```

Environment-specific configuration is supplied through the environment configuration under:

```text
envs/
```

---

# 15. Central Naming and Tags

`local.tf` centralizes common infrastructure configuration.

Important derived values include:

```text
name_prefix
cluster_name
tf_state_bucket
main_domain
dns_zone_id
trace_id
```

Common tags include:

```text
project
env
cluster
trace-id
plane
owner
managed-by
```

The trace ID is derived from the project, environment, and cluster name.

Modules extend these base tags with component-specific information such as:

```text
layer
resource-type
cluster-role
network-role
log-type
sg-scope
storage-type
```

This provides consistent resource identification across the AWS infrastructure.

---

# 16. Infrastructure State

The infrastructure Terraform state is stored in S3.

The current backend uses:

```text
kubapp-tf-state-259183055744
```

with the environment-specific infrastructure state path:

```text
dev/infra/terraform.tfstate
```

State encryption is enabled.

S3 state locking is enabled through:

```text
use_lockfile = true
```

The infrastructure layer also consumes a separate Terraform state for DNS.

---

# 17. Root Module Composition

The root `main.tf` composes the infrastructure modules.

The current module instances are:

```text
module.network
module.sg_prep
module.security
module.iam_core
module.iam_irsa
module.eks
module.logging
module.efs
module.acm
```

The root module passes outputs between components instead of duplicating infrastructure values.

For example:

```text
network
   │
   ├── VPC ID
   └── private subnet IDs
          │
          ├── EKS
          └── EFS
```

and:

```text
iam-core
   │
   ├── cluster role
   ├── node role
   └── Fargate role
          │
          ▼
         EKS
```

and:

```text
EKS
 │
 ├── OIDC ARN
 └── OIDC URL
       │
       ▼
    iam-irsa
```

---

# 18. Infrastructure Dependency Flow

The major dependency relationships are:

```text
DNS Terraform State
        │
        ├──────────────────┐
        ▼                  ▼
   main_domain         dns_zone_id
        │                  │
        │                  ├── ACM
        │                  └── IAM IRSA
        │
        ▼

logging
   │
   ├── VPC Flow Logs
   └── Fargate log group
        │
        ▼

network
   │
   ├── VPC
   ├── public subnets
   ├── private subnets
   ├── IGW
   ├── NAT gateways
   └── routes
        │
        ├───────────────┐
        ▼               ▼
    security           EFS
        │               │
        │               └── EFS SG
        │
        ▼
      EKS
        │
        └── OIDC
              │
              ▼
          iam-irsa
```

The actual Terraform graph is determined by resource references and explicit dependencies.

---

# 19. Infrastructure → Kubernetes Boundary

The most important boundary between the two Terraform layers is the infrastructure outputs.

`iac/infra` exposes information required by `iac/k8s`, including:

* EKS cluster name
* EKS endpoint
* EKS CA certificate
* cluster Security Group ID
* EC2 application Security Group ID
* Fargate application Security Group ID
* workload selectors
* EFS ID
* IAM role ARNs
* CloudWatch log group names
* DNS/domain information
* ACM certificate ARN

The flow is:

```text
iac/infra
    │
    │ Terraform outputs
    ▼
terraform_remote_state
    │
    ▼
iac/k8s
```

This keeps AWS infrastructure ownership in `iac/infra` while allowing the Kubernetes layer to consume the infrastructure it needs.

---

# 20. Overall Infrastructure Flow

The complete infrastructure model is:

```text
                    DNS State
                       │
                       ▼
                 Domain / Zone
                       │
                       ▼
┌──────────────────────────────────────────┐
│                iac/infra                 │
│                                          │
│  network ───────────────┐               │
│                         │               │
│  logging                │               │
│                         ▼               │
│  sg-prep ───────► security              │
│                         │               │
│  iam-core ──────────────┤               │
│                         ▼               │
│                        EKS              │
│                         │               │
│                         ▼               │
│                       OIDC              │
│                         │               │
│                         ▼               │
│                      iam-irsa           │
│                                          │
│  EFS                                      │
│  ACM                                      │
└──────────────────────┬───────────────────┘
                       │
                       │ Terraform outputs
                       ▼
                  ┌──────────┐
                  │ iac/k8s  │
                  └────┬─────┘
                       │
                       ▼
                  Kubernetes
                       │
                       ▼
                    Argo CD
                       │
                       ▼
                   Applications
```

---

# Summary

`iac/infra` is the AWS foundation of KUBAPP.

Its Terraform modules divide infrastructure responsibilities into clear components:

```text
network
security
sg-prep
iam-core
iam-irsa
eks
logging
efs
acm
```

The infrastructure layer establishes:

* AWS networking
* EKS compute
* IAM
* OIDC/IRSA
* workload Security Groups
* persistent storage
* CloudWatch logging
* TLS certificates
* EKS access

It then exposes the required outputs to `iac/k8s`.

The resulting KUBAPP infrastructure boundary is:

```text
DNS
 ↓
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
