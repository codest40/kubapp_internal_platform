# SysMonitor AWS Infrastructure

The `cloud/aws` layer provisions and operates the AWS environment in which SysMonitor runs.

SysMonitor is deployed as a Docker-based monitoring platform on an EC2 instance. Terraform manages the underlying AWS resources and IAM configuration, while the instance bootstrap process installs the runtime dependencies, retrieves required configuration, deploys the application, and starts the services.

The deployment supports both **same-account** and **cross-account** operation against the KUBAPP AWS environment.

## Responsibilities

The AWS layer is responsible for:

* Provisioning the SysMonitor VPC and subnet.
* Provisioning the EC2 host and Elastic IP.
* Configuring security groups and network access.
* Creating and configuring the SysMonitor EC2 IAM role and instance profile.
* Configuring access to KUBAPP resources in same-account or cross-account mode.
* Managing Terraform remote state.
* Reading the KUBAPP infrastructure state required by SysMonitor.
* Managing Route 53 records for SysMonitor services.
* Bootstrapping a new EC2 instance.
* Installing the system and container runtime dependencies.
* Retrieving the GitHub deployment key from AWS Systems Manager Parameter Store.
* Cloning the SysMonitor repository.
* Generating runtime configuration for the deployed services.
* Starting the Docker Compose stack.
* Configuring the public edge, including Nginx and TLS.
* Reporting deployment state through the SysMonitor deployment status mechanism.

The infrastructure layer does not manage the Kubernetes workloads themselves. KUBAPP owns its EKS infrastructure and Kubernetes resources. SysMonitor consumes the resources it has been explicitly granted access to.

## Deployment Architecture

A normal deployment follows this flow:

```text
Terraform
    │
    ├── VPC
    ├── Subnet
    ├── Security Group
    ├── EC2
    ├── Elastic IP
    ├── IAM Role / Instance Profile
    └── DNS / Route 53
          │
          ▼
      EC2 Bootstrap
          │
          ├── Install system dependencies
          ├── Install Docker tooling
          ├── Configure AWS access
          ├── Retrieve deployment secret
          ├── Clone SysMonitor
          ├── Generate .env
          └── Start Docker Compose
                    │
                    ▼
              SysMonitor Services
```

The EC2 instance is therefore the runtime host, while Terraform remains the source of truth for the AWS infrastructure surrounding it.

## Repository Structure

The AWS deployment is divided into Terraform configuration, bootstrap configuration, and runtime scripts.

```text
cloud/aws/
├── boot/
├── assume/
├── main/
├── backend.tf
├── config_local.tf
├── config_cross.tf
├── local.tf
├── providers.tf
├── variables.tf
├── outputs.tf
└── runner.sh
```

The exact contents can evolve as the deployment implementation changes. The important boundary is:

* **Terraform** defines infrastructure and IAM.
* **Bootstrap configuration** prepares prerequisites such as remote state and cross-account access.
* **Runtime scripts** prepare the EC2 host and start SysMonitor.
* **Docker Compose** owns the application services once the host is ready.

## Deployment Modes

SysMonitor supports two AWS access modes for the target KUBAPP environment.

### Local Mode

In local mode, SysMonitor runs in the same AWS account as the target KUBAPP resources.

The EC2 instance uses its own:

```text
sys-monitor-ec2-role
```

to access the target resources.

The application receives AWS credentials through the EC2 instance profile. No static AWS credentials are placed in the application configuration.

### Cross-Account Mode

In cross-account mode, SysMonitor runs in its own AWS account while the target KUBAPP infrastructure resides in another account.

The EC2 instance first obtains credentials through:

```text
sys-monitor-ec2-role
```

in the SysMonitor account.

The application then assumes:

```text
sys-monitor-cross-account-role
```

in the KUBAPP account when accessing KUBAPP resources.

The runtime flow is:

```text
SysMonitor EC2
     │
     │ instance profile
     ▼
sys-monitor-ec2-role
     │
     │ sts:AssumeRole
     ▼
KUBAPP account
sys-monitor-cross-account-role
     │
     ▼
KUBAPP resources
```

This is an application-level AWS authentication flow. SysMonitor does not require a manually created kubeconfig or manually exported AWS credentials to perform its normal EKS monitoring.

## EKS Access

For EKS monitoring, the cross-account role is mapped into the KUBAPP EKS cluster through an EKS Access Entry.

The role is associated with the Kubernetes group:

```text
sys-monitor-gitops
```

Kubernetes RBAC then grants that group only the resources required by the GitOps exporter.

Current permissions include:

```text
nodes
  └── list

argoproj.io/applications
  └── list
```

This separates the responsibilities:

```text
AWS IAM
  → establishes AWS/EKS identity

EKS Access Entry
  → maps the AWS identity into Kubernetes

Kubernetes RBAC
  → defines what SysMonitor can read
```

SysMonitor therefore does not require cluster-admin access to collect its GitOps metrics.

## Runtime Authentication

The GitOps exporter does not depend on the EC2 host having a persistent Kubernetes configuration.

In cross-account mode, its runtime authentication is performed programmatically:

```text
EC2 instance credentials
        │
        ▼
Assume sys-monitor-cross-account-role
        │
        ▼
Describe KUBAPP EKS cluster
        │
        ▼
Obtain EKS authentication token
        │
        ▼
Kubernetes API
        │
        ├── list nodes
        └── list ArgoCD Applications
```

This allows the deployed application to recover its AWS and EKS access automatically whenever the instance and containers are recreated.

Interactive `kubectl` access from an operator is a separate operational workflow and is not a dependency of the SysMonitor application.

## EC2 Bootstrap

A new EC2 instance is prepared by `user_data.sh`.

The bootstrap process installs the dependencies required by the platform, including:

* Git
* Docker
* Docker Buildx
* Docker Compose
* `kubectl`
* AWS tooling
* SSM Agent

The bootstrap process then:

1. Retrieves the GitHub deployment key from SSM Parameter Store.
2. Configures GitHub SSH access.
3. Clones the SysMonitor repository.
4. Loads the appropriate deployment mode.
5. Generates the runtime `.env`.
6. Starts the Docker Compose services.
7. Waits for the services to become healthy.
8. Configures the public edge.
9. Configures TLS and certificate renewal.
10. Marks the deployment as active.

The instance therefore becomes operational from a fresh provision without requiring an operator to manually install or configure the application stack.

## Runtime Configuration

The generated runtime configuration identifies the target environment and, where required, the cross-account role.

For cross-account operation, the application receives configuration equivalent to:

```text
CLUSTER_MODE=cross
TARGET_CLUSTER_NAME=kubapp-dev
TARGET_REGION=us-east-1
TARGET_ROLE_ARN=arn:aws:iam::<kubapp-account>:role/sys-monitor-cross-account-role
```

The application uses the role ARN to establish its target AWS identity at runtime.

Credentials themselves are not stored in this configuration.

## Terraform State

SysMonitor uses S3-backed Terraform state.

The state backend is initialized separately from the main infrastructure deployment so that the state storage exists before Terraform attempts to manage the rest of the environment.

The deployment can consume KUBAPP's Terraform state to obtain infrastructure information such as:

* EKS cluster name.
* Domain information.
* Other exported infrastructure values required by SysMonitor.

In cross-account mode, access to KUBAPP state is performed through the Terraform-specific cross-account role. The runtime application role and the Terraform provisioning role have separate responsibilities.

```text
Terraform provisioning
        │
        ▼
sys-monitor-terraform-role
        │
        ▼
KUBAPP Terraform state / infrastructure

Application runtime
        │
        ▼
sys-monitor-cross-account-role
        │
        ▼
KUBAPP runtime resources
```

This separation prevents the application runtime identity from becoming the Terraform administration identity.

## Access and Operations

The deployment supports both SSM and SSH-based administrative access.

SSM is the preferred management path when enabled because it does not require exposing an SSH service to the public network.

SSH access can be enabled when required by the deployment configuration.

The application itself does not depend on either access method once the EC2 bootstrap has completed.

## Deployment Lifecycle

A complete deployment is treated as an infrastructure lifecycle rather than a collection of manual setup steps.

```text
apply
  │
  ▼
AWS infrastructure
  │
  ▼
EC2 bootstrap
  │
  ▼
SysMonitor containers
  │
  ▼
Health checks
  │
  ▼
Edge / TLS
  │
  ▼
active
```

A destroy operation removes the provisioned environment and updates the SysMonitor deployment state accordingly.

This allows the deployment status mechanism to distinguish an active SysMonitor environment from one that has been destroyed or is unavailable.

## Operational Boundary

The AWS layer owns **where and how SysMonitor runs**.

The application layer owns **what SysMonitor monitors**.

KUBAPP owns the target Kubernetes infrastructure and its Kubernetes authorization model.

This separation is intentional:

```text
SysMonitor AWS
    → provision and run SysMonitor

SysMonitor application
    → collect and expose operational data

KUBAPP infrastructure
    → provision EKS and AWS resources

KUBAPP Kubernetes layer
    → control Kubernetes access
```

Changes to one boundary should not require giving the other component unnecessary administrative privileges.
