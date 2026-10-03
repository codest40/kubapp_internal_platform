# SysMonitor AWS Setup

This document describes how to provision and run SysMonitor on AWS.

The AWS deployment is driven through the `cloud/aws` entrypoints. Operators should use these entrypoints rather than running the individual Terraform configurations directly.

The deployment supports:

* **local mode** — SysMonitor and KUBAPP resources are in the same AWS account.
* **cross mode** — SysMonitor runs in a separate AWS account and assumes a dedicated role in the KUBAPP account.
* **SSM access** — administrative access through AWS Systems Manager.
* **SSH access** — optional direct SSH access.

---

## Prerequisites

The deployment host must have:

* AWS CLI
* Terraform
* Git
* Bash
* An authenticated AWS CLI profile for the selected deployment mode.

Verify:

```bash
aws --version
terraform version
git --version
```

The AWS identity used for deployment must have permission to create and manage the resources required by SysMonitor.

For cross-account deployments, the deployment identity must also be able to perform the required bootstrap operations in both AWS accounts.

---

## Repository

From the repository root:

```bash
cd sys_monitor/cloud/aws
```

The main deployment entrypoints are:

```text
init_tf.sh       Terraform state bootstrap
runner.sh        SysMonitor infrastructure lifecycle
setup.env        Deployment configuration
```

Supporting files such as `helpers.sh` and `manage_provider.sh` are called by the entrypoints and normally do not need to be executed directly.

---

## Configuration

Deployment configuration is stored in:

```text
cloud/aws/setup.env
```

The file defines the environment, AWS accounts, profiles, region, deployment mode, instance configuration, and access mode used by the deployment scripts.

The important settings are:

```text
ENV
CLUSTER_MODE
SYS_MONITOR_ACCOUNT_ID
KUBAPP_ACCOUNT_ID
PROFILE_LOCAL
PROFILE_CROSS
REGION
SYS_MONITOR_INSTANCE_TYPE
ACCESS_MODE
SYS_MONITOR_KEY_NAME
```

### Cluster mode

`CLUSTER_MODE` determines how SysMonitor accesses KUBAPP:

```bash
CLUSTER_MODE=local
```

or:

```bash
CLUSTER_MODE=cross
```

Use `local` when SysMonitor operates in the KUBAPP AWS account.

Use `cross` when SysMonitor operates in a separate AWS account and accesses KUBAPP through the dedicated cross-account IAM role.

### Access mode

`ACCESS_MODE` controls administrative access to the SysMonitor EC2 instance:

```bash
ACCESS_MODE=ssm
```

or:

```bash
ACCESS_MODE=ssh
```

SSM does not require an inbound SSH service.

SSH mode provisions the resources required for SSH-based administration.

---

# First-Time Deployment

A new environment has two stages:

1. Bootstrap Terraform state.
2. Provision the SysMonitor runtime.

## 1. Configure AWS profiles

Make sure the profiles referenced by `setup.env` exist locally.

For example:

```bash
aws sts get-caller-identity --profile <profile>
```

Verify the identities before starting the deployment.

For a cross-account deployment, verify both the SysMonitor-side and KUBAPP-side administrative identities.

---

## 2. Bootstrap Terraform State

Run:

```bash
./init_tf.sh apply
```

This creates the Terraform state infrastructure required by the SysMonitor deployment.

The bootstrap process creates:

* the SysMonitor Terraform state bucket.
* the active-mode state configuration.
* the runtime Terraform state configuration.

The active state path depends on `CLUSTER_MODE`.

For example:

```text
local:
<env>/sys-monitor-local/tf-state

cross:
<env>/sys-monitor-cross/tf-state
```

The runtime infrastructure uses:

```text
<env>/sys-monitor-runtime/tf-state
```

State bootstrap only needs to be performed when creating a new environment or when the state infrastructure itself has been removed.

---

## 3. Provision SysMonitor

After state bootstrap completes:

```bash
./runner.sh apply
```

The runner performs the deployment in order.

### Identity bootstrap

The deployment first provisions the IAM identity required by the SysMonitor EC2 instance.

In cross-account mode this establishes the identity required for the SysMonitor account to access the KUBAPP account.

### Runtime infrastructure

The deployment then initializes Terraform for the runtime infrastructure and provisions the configured AWS resources.

These include the resources required to run SysMonitor, such as:

* VPC networking.
* Subnet.
* Security group.
* EC2 instance.
* Elastic IP.
* IAM instance profile.
* DNS resources where configured.

### EC2 bootstrap

Once the EC2 instance starts, its bootstrap process:

1. Installs required system packages.
2. Starts SSM Agent and Docker.
3. Installs Docker Buildx.
4. Installs Docker Compose.
5. Installs `kubectl`.
6. Retrieves the GitHub deployment key from SSM Parameter Store.
7. Clones the SysMonitor repository.
8. Configures the runtime environment.
9. Starts the Docker Compose services.
10. Waits for service health checks.
11. Configures the public edge.
12. Configures TLS and certificate renewal.

The instance is therefore responsible for preparing and starting the application; Terraform remains responsible for the AWS infrastructure.

---

# Cross-Account Deployment

Cross-account mode does not require an operator to manually assume the SysMonitor runtime role after deployment.

The runtime identity is provided by the EC2 instance profile:

```text
SysMonitor account
        │
        ▼
sys-monitor-ec2-role
        │
        │ AssumeRole
        ▼
KUBAPP account
        │
        ▼
sys-monitor-cross-account-role
```

The SysMonitor application uses this role when accessing KUBAPP resources.

For EKS monitoring, the cross-account role is mapped to the Kubernetes group:

```text
sys-monitor-gitops
```

The corresponding Kubernetes RBAC grants the GitOps exporter the read permissions required to collect its metrics.

The application does **not** depend on an operator manually running:

```bash
aws sts assume-role
```

or:

```bash
aws eks update-kubeconfig
```

Those commands may be used separately by an operator for interactive AWS or Kubernetes administration, but they are not part of the SysMonitor application's runtime dependency chain.

---

# Planning a Deployment

To inspect the changes without applying them:

```bash
./runner.sh plan
```

The runner performs the identity planning and runtime Terraform planning for the selected mode.

For state bootstrap planning:

```bash
./init_tf.sh plan
```

No infrastructure changes are made by either command.

---

# Applying Changes

Apply the complete SysMonitor runtime:

```bash
./runner.sh apply
```

The runner performs the required identity and runtime Terraform operations.

A successful runtime deployment updates the SysMonitor deployment status to:

```text
active
```

---

# Destroying the Environment

To remove the SysMonitor runtime:

```bash
./runner.sh destroy
```

The command requires confirmation unless automatic confirmation is supplied.

For non-interactive execution:

```bash
./runner.sh destroy -y
```

The runtime is destroyed before the identity bootstrap is removed.

The deployment status is updated to:

```text
inactive
```

### Destroying Terraform State

State infrastructure is separate from the runtime.

To destroy the state bootstrap:

```bash
./init_tf.sh destroy
```

This removes the state resources managed by the bootstrap configuration, including the state bucket.

Do not destroy state infrastructure as part of a normal application or EC2 teardown. The state bootstrap should remain available when the runtime is expected to be recreated.

---

# Deployment Verification

After:

```bash
./runner.sh apply
```

### Cross-Account Status Coordination

The sys_monitor deployment writes its current lifecycle state to:

```text
cloud/aws/store/status
```

This status is primarily used by **KUBAPP infrastructure**, not as a runtime health check for sys_monitor.

The purpose is to coordinate the dependency between the two platforms:

```text
sys_monitor
    │
    │ identity exists / is removed
    ▼
store/status
    │
    ▼
KUBAPP iac/infra
    │
    ├── enable cross-account resources
    ├── create/update required IAM access
    └── create/update EKS access entries
            │
            ▼
      sys_monitor cross mode
```

When sys_monitor is provisioned in cross-account mode, the status allows KUBAPP infrastructure to determine whether the sys_monitor-side identity is available before creating resources that depend on it.

This avoids KUBAPP attempting to create cross-account IAM or EKS resources against a sys_monitor principal that does not currently exist.

The coordination flow is therefore:

1. sys_monitor identity is provisioned.
2. sys_monitor records its lifecycle state.
3. KUBAPP infrastructure consumes that state.
4. KUBAPP creates the required cross-account resources when the sys_monitor identity is available.
5. sys_monitor can then start its cross-account runtime against those resources.
6. When the sys_monitor infrastructure is destroyed, its state is updated so KUBAPP can stop managing the dependent cross-account resources.

The status file is therefore a **Terraform/IaC coordination mechanism between KUBAPP and sys_monitor**. It should not be interpreted as:

* application health
* service readiness
* EC2 health
* Docker Compose health
* Kubernetes health
* monitoring status

Runtime health is determined independently through the services, monitoring stack, and application-specific health checks.

Verify the EC2 instance through AWS:

```bash
aws ec2 describe-instances \
  --profile <profile> \
  --region <region>
```

If SSM access is enabled, connect using:

```bash
aws ssm start-session \
  --profile <profile> \
  --region <region> \
  --target <instance-id>
```

On the EC2 instance, verify the services:

```bash
sudo docker compose ps
```

The deployed SysMonitor services should be running.

---

# Service Verification

The bootstrap process checks the local service endpoints before declaring the edge ready.

The primary services include:

```text
Prometheus       : 9090
Grafana          : 3001
GitHub exporter  : 3000
GitOps exporter  : 9105
Codebase exporter: 8080
```

Check the GitOps exporter:

```bash
curl http://localhost:9105/
```

Expected:

```text
GitOps Exporter Running
```

Check its Prometheus metrics:

```bash
curl http://localhost:9105/metrics
```

Prometheus should be able to scrape the exporter and expose the resulting metrics through the monitoring stack.

---

# Cross-Account EKS Verification

The application's cross-account EKS access is automatic and does not require kubeconfig.

The GitOps exporter establishes its AWS identity programmatically:

```text
EC2 instance profile
        │
        ▼
sys-monitor-ec2-role
        │
        ▼
AssumeRole
        │
        ▼
sys-monitor-cross-account-role
        │
        ▼
EKS authentication
        │
        ▼
Kubernetes API
```

The exporter then reads the Kubernetes resources required for GitOps monitoring.

Operator `kubectl` access is separate from this runtime flow.

If interactive Kubernetes administration is required, an operator can configure `kubectl` independently using the appropriate AWS credentials and EKS access.

---

# Provider Selection

The deployment supports separate Terraform configurations for local and cross-account operation.

The active configuration is selected automatically from:

```text
CLUSTER_MODE
```

For example:

```text
CLUSTER_MODE=local
```

activates the local provider configuration.

```text
CLUSTER_MODE=cross
```

activates the cross-account provider configuration.

Operators should not manually copy, delete, or rename the provider configuration files. `runner.sh` and `manage_provider.sh` manage the active configuration.

---

# Typical Workflows

## New local deployment

```bash
cd sys_monitor/cloud/aws

# configure setup.env

./init_tf.sh apply
./runner.sh apply
```

## New cross-account deployment

```bash
cd sys_monitor/cloud/aws

# configure setup.env with CLUSTER_MODE=cross

./init_tf.sh apply
./runner.sh apply
```

## Review changes

```bash
./runner.sh plan
```

## Apply changes

```bash
./runner.sh apply
```

## Remove runtime

```bash
./runner.sh destroy
```

## Remove state infrastructure

```bash
./init_tf.sh destroy
```

---

# Troubleshooting

### Configuration validation fails

Check:

```bash
cat setup.env
```

The deployment requires the mandatory variables used by `runner.sh` and `init_tf.sh`.

### AWS identity failure

Verify the configured profile:

```bash
aws sts get-caller-identity --profile <profile>
```

Then verify that the selected profile corresponds to the expected AWS account.

### State bootstrap failure

Run:

```bash
./init_tf.sh plan
```

This separates state infrastructure problems from the main SysMonitor runtime deployment.

### Runtime Terraform failure

Run:

```bash
./runner.sh plan
```

Review the Terraform plan before attempting another apply.

### EC2 service failure

Connect to the instance and inspect:

```bash
sudo docker compose ps
sudo docker compose logs
```

The EC2 bootstrap log is available at:

```bash
sudo cat /var/log/user-data.log
```

### GitOps EKS access failure

First inspect the GitOps exporter:

```bash
sudo docker logs gitops-exporter
```

The expected cross-account runtime identity is:

```text
sys-monitor-ec2-role
        ↓
sys-monitor-cross-account-role
```

EKS authorization is then controlled by the EKS Access Entry and Kubernetes RBAC configuration owned by KUBAPP.
Do not resolve an application authentication failure by manually adding AWS credentials to the container. The intended runtime model is IAM-based authentication through the EC2 instance role and the configured cross-account role.
