# SysMonitor AWS

The `cloud/aws` layer provisions and operates the AWS environment in which SysMonitor runs.

SysMonitor runs as a Docker-based monitoring platform on an EC2 instance. Terraform manages the AWS infrastructure, IAM, networking, DNS, and deployment lifecycle, while the EC2 bootstrap prepares the host and starts the application runtime.

The deployment supports both **local** and **cross-account** operation against KUBAPP.

For workstation preparation, AWS profile configuration, credentials, GitHub access, SSM configuration, and first-time environment setup, see [`SETUP.md`](./SETUP.md).

---

## Architecture

The AWS layer establishes the infrastructure boundary around the SysMonitor application:

```text
Terraform
    │
    ├── Networking
    ├── Security Groups
    ├── EC2
    ├── Elastic IP
    ├── IAM
    ├── DNS
    └── Terraform State
          │
          ▼
      EC2 Bootstrap
          │
          ├── Host dependencies
          ├── GitHub access
          ├── Runtime configuration
          └── Docker Compose
                    │
                    ▼
             SysMonitor Services
```

Terraform is the source of truth for the AWS infrastructure.

The EC2 instance is the runtime host.

Docker Compose owns the SysMonitor application services after the host has been prepared.

---

## Responsibilities

The AWS layer is responsible for:

* AWS networking required by SysMonitor.
* EC2 infrastructure.
* Elastic IP and security groups.
* SysMonitor IAM roles and instance profile.
* Terraform remote state.
* DNS and public edge configuration.
* EC2 bootstrap.
* Runtime host preparation.
* Deployment of the SysMonitor container stack.
* Cross-account AWS access where enabled.
* Coordination with KUBAPP infrastructure.

The AWS layer does not manage KUBAPP's Kubernetes workloads.

KUBAPP owns its EKS infrastructure and Kubernetes authorization model. SysMonitor consumes only the resources to which it has explicitly been granted access.

---

## Deployment Modes

SysMonitor supports two deployment modes.

### Local

In local mode, SysMonitor operates against KUBAPP resources within the same AWS account boundary.

The EC2 runtime uses:

```text
sys-monitor-ec2-role
```

as its AWS identity.

The application obtains AWS credentials from the EC2 instance profile rather than from static credentials stored in application configuration.

---

### Cross-Account

In cross-account mode, SysMonitor runs in a separate AWS account from KUBAPP.

The EC2 instance receives:

```text
sys-monitor-ec2-role
```

through its instance profile.

When access to KUBAPP resources is required, the application assumes:

```text
sys-monitor-cross-account-role
```

in the KUBAPP account.

The runtime relationship is:

```text
SysMonitor EC2
      │
      │ instance profile
      ▼
sys-monitor-ec2-role
      │
      │ AssumeRole
      ▼
KUBAPP account
      │
      ▼
sys-monitor-cross-account-role
      │
      ▼
KUBAPP resources
```

The runtime role and Terraform provisioning role are separate identities with separate responsibilities.

---

## EKS Access

When SysMonitor monitors KUBAPP EKS, AWS authentication and Kubernetes authorization are separate layers.

The cross-account IAM role is registered with the EKS cluster through an EKS Access Entry and mapped to:

```text
sys-monitor-gitops
```

Kubernetes RBAC grants that group only the resources required by the monitoring application.

The current GitOps exporter requires:

```text
nodes
  └── list

argoproj.io/applications
  └── list
```

The authorization chain is therefore:

```text
AWS IAM
    │
    │ establishes AWS identity
    ▼
EKS Access Entry
    │
    │ maps identity
    ▼
Kubernetes group
    │
    │ sys-monitor-gitops
    ▼
Kubernetes RBAC
    │
    ├── nodes:list
    └── applications:list
```

SysMonitor does not require Kubernetes cluster-admin privileges for this monitoring path.

---

## Runtime Kubernetes Authentication

The SysMonitor application does not depend on a persistent kubeconfig on the EC2 host.

The GitOps exporter establishes its Kubernetes connection programmatically.

In cross-account mode:

```text
EC2 credentials
      │
      ▼
sys-monitor-ec2-role
      │
      │ AssumeRole
      ▼
sys-monitor-cross-account-role
      │
      ▼
EKS cluster information
      │
      ▼
EKS authentication token
      │
      ▼
Kubernetes API
```

This allows the application to recreate its AWS and Kubernetes access when the EC2 host or containers are recreated.

An operator may use `kubectl` independently for administration and troubleshooting, but an operator-managed kubeconfig is not a dependency of the SysMonitor runtime.

---

## Terraform State

SysMonitor uses S3-backed Terraform state.

State infrastructure is initialized separately from the main runtime infrastructure so that the backend exists before the main Terraform configuration uses it.

SysMonitor also consumes selected outputs from KUBAPP infrastructure state. These outputs provide information required to configure resources such as the target EKS cluster and domain.

The Terraform provisioning identity is separate from the runtime identity:

```text
Terraform
    │
    ▼
sys-monitor-terraform-role
    │
    ▼
KUBAPP Terraform state / infrastructure


SysMonitor runtime
    │
    ▼
sys-monitor-cross-account-role
    │
    ▼
KUBAPP runtime resources
```

This prevents the application runtime identity from becoming a Terraform administration identity.

---

## `store/status` Coordination

The AWS deployment maintains:

```text
store/status
```

as a coordination mechanism between SysMonitor and KUBAPP infrastructure.

It is **not a SysMonitor health indicator**.

The status communicates whether the SysMonitor deployment has reached the lifecycle state required for KUBAPP to provision or retain its dependent cross-account resources.

The expected states are:

```text
active
inactive
```

### Active

After a successful SysMonitor deployment, `runner.sh` records:

```text
active
```

This indicates that the SysMonitor-side infrastructure and identity required for the cross-account relationship are available.

KUBAPP infrastructure can use this state when deciding whether its SysMonitor cross-account resources should be enabled.

### Inactive

After a successful SysMonitor destroy operation, `runner.sh` records:

```text
inactive
```

This indicates that the SysMonitor deployment is no longer available for that cross-account relationship.

KUBAPP infrastructure can use this state when deciding whether dependent cross-account resources should be removed or disabled.

### Coordination flow

```text
SysMonitor
    │
    ├── deploy ──────► store/status = active
    │                         │
    │                         ▼
    │                    KUBAPP IaC
    │                         │
    │                         ▼
    │                  cross-account resources
    │
    └── destroy ─────► store/status = inactive
                              │
                              ▼
                         KUBAPP IaC
                              │
                              ▼
                    dependent resources
```

The status mechanism therefore coordinates **infrastructure lifecycle between the two platforms**.

It does not represent:

* EC2 health
* Docker health
* Prometheus health
* Grafana health
* Kubernetes health
* application availability

Those concerns are handled by the platform's runtime and observability mechanisms.

---

## EC2 Runtime

EC2 is the runtime host for SysMonitor.

A newly provisioned instance is prepared through the bootstrap process, which installs the dependencies required to run the platform and then starts the Docker Compose environment.

The bootstrap establishes the runtime from the infrastructure definition rather than requiring the operator to manually configure the host.

At a high level:

```text
EC2 provisioned
      │
      ▼
Bootstrap
      │
      ├── system dependencies
      ├── Docker tooling
      ├── GitHub access
      ├── runtime configuration
      └── application source
      │
      ▼
Docker Compose
      │
      ▼
SysMonitor
```

Detailed bootstrap prerequisites and workstation configuration are documented in [`SETUP.md`](./SETUP.md).

---

# Entry Points

The AWS layer exposes two primary operational entry points:

```text
init_tf.sh
runner.sh
```

They have different responsibilities.

---

## `init_tf.sh`

`init_tf.sh` manages the Terraform state infrastructure required by the deployment.

It is responsible for establishing the S3-backed state environment before the main runtime Terraform configuration uses it.

### Apply

```bash
./init_tf.sh apply
```

Creates or prepares the required Terraform state infrastructure.

### Plan

```bash
./init_tf.sh plan
```

Shows the changes that would be made to the state infrastructure.

### Destroy

```bash
./init_tf.sh destroy
```

Removes the Terraform state infrastructure.

State destruction is separate from destroying the SysMonitor runtime. The normal runtime lifecycle does not require destroying the state backend.

---

## `runner.sh`

`runner.sh` is the main SysMonitor infrastructure lifecycle entry point.

It manages the selected deployment mode, identity bootstrap, Terraform provider configuration, main Terraform backend, runtime infrastructure, and deployment-state coordination.

### Plan

```bash
./runner.sh plan
```

Runs the deployment through the planning path without applying the resulting infrastructure changes.

### Apply

```bash
./runner.sh apply
```

Runs the complete SysMonitor infrastructure deployment.

At a high level:

```text
runner.sh apply
      │
      ▼
Configuration
      │
      ▼
Identity bootstrap
      │
      ▼
Provider selection
      │
      ▼
Terraform initialization
      │
      ▼
Terraform plan
      │
      ▼
Terraform apply
      │
      ▼
Deployment status
      │
      ▼
SysMonitor runtime
```

A successful apply records the appropriate deployment state in:

```text
store/status
```

---

### Destroy

```bash
./runner.sh destroy
```

Destroys the SysMonitor runtime infrastructure.

The command requires confirmation unless explicitly run in automatic mode:

```bash
./runner.sh destroy -y
```

After a successful destroy, the deployment status is changed to:

```text
inactive
```

This allows KUBAPP infrastructure to recognize that the SysMonitor-side cross-account dependency is no longer available.

---

# Lifecycle

The two entry points work together:

```text
             init_tf.sh
                  │
                  ▼
        Terraform state backend
                  │
                  │
                  ▼
             runner.sh
                  │
          ┌───────┴───────┐
          │               │
        apply           destroy
          │               │
          ▼               ▼
    AWS infrastructure   remove runtime
          │               │
          ▼               ▼
       EC2 runtime    status = inactive
          │
          ▼
    status = active
```

The state bootstrap is therefore a prerequisite layer, while `runner.sh` manages the actual SysMonitor environment.

---

## Operational Boundary

The AWS layer defines **where and how SysMonitor runs**.

The SysMonitor application defines **what operational data it collects and exposes**.

KUBAPP defines **the target AWS and Kubernetes infrastructure**.

The boundaries are:

```text
SysMonitor AWS
    │
    └── provision and operate SysMonitor runtime

SysMonitor application
    │
    └── collect and expose monitoring data

KUBAPP AWS infrastructure
    │
    └── provision target AWS resources and EKS

KUBAPP Kubernetes layer
    │
    └── authorize SysMonitor's Kubernetes access
```

Each layer retains only the permissions and responsibilities required for its role.

---

## Documentation

Use:

```text
README.md
```

for the architecture, responsibilities, deployment model, lifecycle, and operational entry points.

Use:

```text
SETUP.md
```

for workstation preparation, AWS profiles, credentials, GitHub access, SSM configuration, deployment prerequisites, environment configuration, and step-by-step deployment verification.

