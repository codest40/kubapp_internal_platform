# SysMonitor — AWS Setup Guide

This document describes how to prepare, deploy, verify, and manage the SysMonitor AWS environment.

The deployment is designed to be reproducible from a fresh machine. The required AWS credentials, profiles, Terraform state, IAM roles, deployment keys, and runtime configuration must be established before the main deployment is started.

SysMonitor supports two AWS operating modes:

* **Local mode** — SysMonitor and the target KubApp resources are managed from the same AWS account.
* **Cross-account mode** — SysMonitor runs in its own AWS account and assumes a dedicated IAM role in the KubApp account when it needs access to KubApp resources such as EKS.

The deployment is driven through:

```text
aws/
├── bootstrap/
├── main/
├── runner.sh
├── init_tf.sh
├── manage_provider.sh
├── helpers.sh
├── setup.env
└── store/
```

`runner.sh` is the main operational entrypoint.

---

# 1. Deployment Architecture

The AWS deployment consists of several layers.

```text
Developer workstation
        │
        ├── AWS CLI profiles
        ├── Terraform
        ├── Git / SSH
        │
        ▼
SysMonitor AWS runner
        │
        ├── Identity bootstrap
        ├── Terraform state bootstrap
        ├── Main infrastructure
        └── EC2 application deployment
        │
        ▼
SysMonitor EC2
        │
        ├── IAM instance profile
        ├── SSM
        ├── Docker
        ├── SysMonitor services
        └── GitOps exporter
        │
        ▼
KubApp AWS account
        │
        ├── EKS
        ├── IAM
        └── cross-account access
```

Cross-account operation adds an additional trust path:

```text
SysMonitor EC2
    │
    │ sys-monitor-ec2-role
    │
    ▼
AssumeRole
    │
    ▼
KubApp account
    │
    └── sys-monitor-cross-account-role
            │
            └── EKS / other permitted resources
```

The application does not depend on a manually generated kubeconfig for its Kubernetes access.

The GitOps service obtains AWS credentials programmatically, assumes the configured cross-account role when required, obtains an EKS authentication token, and creates its Kubernetes clients.

---

# 2. Prerequisites

The deployment requires:

* Linux workstation
* AWS CLI
* Terraform
* Git
* OpenSSH client
* Bash
* Python 3
* Network access to AWS
* Network access to GitHub
* An AWS identity with the permissions required to bootstrap the environment

The workstation must also have access to the SysMonitor repository.

---

# 3. AWS CLI Installation and Authentication

Install the AWS CLI using the official AWS installation method for the workstation operating system.

Verify:

```bash
aws --version
```

Example:

```text
aws-cli/2.x.x ...
```

The AWS CLI is used by:

* Terraform provider configuration
* Terraform backend access
* bootstrap scripts
* IAM operations
* SSM operations
* deployment verification
* cross-account role assumption

AWS credentials must be configured before running Terraform.

Verify the base credentials:

```bash
aws sts get-caller-identity
```

This must return the expected AWS account and identity.

Do not proceed to Terraform until this command succeeds.

---

# 4. Required AWS Profiles

SysMonitor uses AWS profiles to separate the credentials used for local and cross-account operations.

The names configured by the deployment are:

```text
PROFILE_LOCAL
PROFILE_CROSS
```

These values are defined in:

```text
sys_monitor/cloud/aws/setup.env
```

A typical configuration may look like:

```bash
PROFILE_LOCAL="admin-profile"
PROFILE_CROSS="sys-monitor"
```

The actual profile names can be different, but they must correspond to valid profiles in:

```text
~/.aws/config
~/.aws/credentials
```

The important requirement is that the profile referenced as `PROFILE_CROSS` is capable of assuming the KubApp-side role required by the cross-account deployment.

---

# 5. Why the `sys-monitor` AWS Profile Exists

The `sys-monitor` profile is used for the AWS identity that operates the SysMonitor side of the cross-account deployment.

It is particularly important because Terraform needs a credential source from which it can assume the appropriate role.

The profile does **not** mean that Terraform permanently operates as the target KubApp role.

Instead, the credential chain is:

```text
source credentials
       │
       ▼
sys-monitor AWS profile
       │
       ▼
Terraform AWS provider
       │
       ▼
assume_role
       │
       ▼
target AWS role
```

This separation makes the credential flow explicit and prevents the deployment from depending on manually exported temporary credentials.

---

# 6. Configure the `sys-monitor` Profile

The `sys-monitor` profile should be configured in:

```text
~/.aws/config
```

For example:

```ini
[profile sys-monitor]
role_arn = arn:aws:iam::<KUBAPP_ACCOUNT_ID>:role/sys-monitor-cross-account-role
source_profile = <SOURCE_PROFILE>
region = us-east-1
```

The source profile must contain credentials capable of assuming the target role.

For example:

```ini
[profile source-profile]
region = us-east-1
```

with the corresponding credentials configured through the normal AWS credential mechanism.

The exact source profile depends on the operator's environment.

Do not hard-code credentials into the repository.

---

# 7. Verify the `sys-monitor` Profile

Before running Terraform, verify the profile independently.

Run:

```bash
aws sts get-caller-identity --profile sys-monitor
```

The returned identity should correspond to the role expected from the profile.

For cross-account operation, the result should show the assumed:

```text
sys-monitor-cross-account-role
```

If this fails, do not proceed to Terraform.

Common causes include:

* incorrect `source_profile`
* missing source credentials
* incorrect `role_arn`
* missing `sts:AssumeRole` permission
* incorrect trust policy on the target role
* incorrect AWS account
* expired or invalid credentials

The AWS profile must work independently before Terraform is introduced.

---

# 8. AWS Account and IAM Prerequisites

The deployment requires the appropriate AWS resources and permissions on both sides when cross-account mode is used.

## SysMonitor account

The SysMonitor account must permit creation of the resources required by the deployment, including:

* VPC/networking resources
* EC2
* Elastic IP
* security groups
* IAM roles
* IAM instance profiles
* SSM-related resources
* Route 53 resources where enabled
* supporting infrastructure

The EC2 instance uses:

```text
sys-monitor-ec2-role
```

as its runtime IAM role.

This role provides the permissions required by the SysMonitor EC2 host.

---

## KubApp account

Cross-account mode requires KubApp to provide:

```text
sys-monitor-cross-account-role
```

This role is assumed by the SysMonitor side.

Its trust relationship must allow the appropriate SysMonitor identity to assume it.

Its permissions must provide only the AWS resources that SysMonitor is intended to access.

For EKS, the role must have the required AWS permissions such as:

```text
eks:DescribeCluster
```

and the corresponding Kubernetes access must also be configured in the EKS cluster.

AWS IAM permission alone is not sufficient for Kubernetes API authorization.

---

# 9. EKS Access for Cross-Account Operation

Cross-account EKS access consists of two separate authorization layers.

## AWS layer

The assumed role must be allowed to call the required EKS APIs.

For example:

```text
eks:DescribeCluster
```

## Kubernetes layer

The same IAM principal must also have an EKS access entry and an appropriate Kubernetes access policy or RBAC configuration.

The current KubApp configuration uses:

```text
sys-monitor-cross-account-role
```

as the EKS principal.

The KubApp infrastructure therefore needs to create/configure the corresponding EKS access entry before SysMonitor attempts to use the cluster.

This is one reason the deployment order matters.

---

# 10. Terraform Installation

Install Terraform on the deployment workstation.

Verify:

```bash
terraform version
```

The installed version must satisfy the version requirements defined by the repository.

Do not proceed if Terraform is unavailable or the installed version is incompatible with the repository configuration.

---

# 11. Git and SSH Access

The deployment workstation must be able to clone and update the repository.

Verify Git:

```bash
git --version
```

Verify GitHub SSH access:

```bash
ssh -T git@github.com
```

The repository should be accessible using SSH.

SysMonitor's EC2 bootstrap also requires GitHub access because the instance obtains the application source code during provisioning.

---

# 12. GitHub Deploy Key and SSM

The SysMonitor EC2 instance does not depend on an operator's local SSH private key.

Instead, the deployment uses an application-specific GitHub deploy key.

The deployment manages two encrypted configuration parameters in AWS Systems Manager Parameter Store:

```text
/sys-monitor/backend/env
/sys-monitor/github/deploy-key
```

The first parameter contains the backend environment configuration. The second contains the private GitHub deploy key required to retrieve the SysMonitor repository.

Both parameters are provisioned by Terraform. They do not need to be created manually in Parameter Store.

## Prepare and encrypt the secrets

The required source files are:

```text
sys_monitor/backend/.env
~/.ssh/sys_monitor_deploy
```

The deployment uses SOPS to encrypt these files into:

```text
sys_monitor/cloud/aws/store/secrets/backend.env.enc
sys_monitor/cloud/aws/store/secrets/github-deploy-key.env.enc
```

Prepare both encrypted files before running the Terraform deployment. Use the AWS runner's secret-encryption operation:

```bash
./runner.sh encrypt
```

The encryption operation requires SOPS to be installed and configured for the repository's encryption setup. Both source files must be available.

The encrypted files are the inputs used by the runner to supply the secret values to Terraform.

## Terraform-managed parameters

During the Terraform deployment, the secret values are used to provision these SSM Parameter Store parameters as `SecureString` values:

| Parameter | Purpose |
|---|---|
| `/sys-monitor/backend/env` | Backend environment configuration |
| `/sys-monitor/github/deploy-key` | Private GitHub deploy key |

Terraform also configures the EC2 runtime role's Parameter Store permissions for these two parameters.

The runtime role receives `ssm:GetParameter` access to the specific parameters rather than unrestricted access to Parameter Store.

## Runtime retrieval

The EC2 instance retrieves the GitHub deploy key using:

```bash
aws ssm get-parameter \
    --name /sys-monitor/github/deploy-key \
    --with-decryption
```

The key is written to:

```text
/root/.ssh/sys_monitor_deploy
```

The EC2 bootstrap then configures Git to use the key when communicating with GitHub.

The backend configuration is retrieved from:

```text
/sys-monitor/backend/env
```

The relationship is:

```text
Local secret files
        │
        ▼
SOPS encryption
        │
        ▼
Encrypted files in store/secrets/
        │
        ▼
Terraform
        │
        ├── /sys-monitor/backend/env
        │
        └── /sys-monitor/github/deploy-key
                    │
                    ▼
             EC2 runtime role
                    │
                    ▼
          AWS SSM Parameter Store
                    │
                    ▼
             SysMonitor EC2
```

The EC2 instance therefore does not require the operator's personal GitHub SSH key.

The GitHub deploy key must have access to the repository.

**Important:** Terraform's `sensitive` variable designation redacts sensitive values from normal CLI output, but it does not prevent those values from being stored in Terraform state. Protect the state backend and restrict access to it accordingly.

---

# 13. Configure `setup.env`

Before running the AWS entrypoint, configure:

```text
sys_monitor/cloud/aws/setup.env
```

The file contains environment-specific deployment settings.

At minimum, the required values include:

```bash
ENV="dev"

CLUSTER_MODE="cross"

SYS_MONITOR_ACCOUNT_ID="<SYS_MONITOR_ACCOUNT_ID>"
KUBAPP_ACCOUNT_ID="<KUBAPP_ACCOUNT_ID>"

PROFILE_LOCAL="<LOCAL_PROFILE>"
PROFILE_CROSS="sys-monitor"

REGION="us-east-1"

SYS_MONITOR_INSTANCE_TYPE="<INSTANCE_TYPE>"

ACCESS_MODE="ssm"

SYS_MONITOR_KEY_NAME="sys-monitor"
```

The exact values depend on the deployment environment.

Do not commit secrets or long-lived credentials into `setup.env`.

---

# 14. Deployment Modes

SysMonitor supports two modes.

## Local mode

In local mode, SysMonitor and the target AWS infrastructure operate in the same account.

The runner selects:

```text
PROFILE_LOCAL
```

and uses the local state configuration.

The identity bootstrap uses:

```text
bootstrap/identity/local/
```

The main Terraform deployment uses the local provider configuration.

---

## Cross-account mode

In cross-account mode, SysMonitor runs in its own AWS account and accesses KubApp resources through:

```text
sys-monitor-cross-account-role
```

The runner selects:

```text
PROFILE_CROSS
```

and uses the cross-account identity configuration.

The identity bootstrap uses:

```text
bootstrap/identity/cross/
```

The main Terraform deployment activates:

```text
config_cross.tf
```

instead of:

```text
config_local.tf
```

The provider configuration is switched by:

```bash
manage_provider.sh
```

This keeps the local and cross-account Terraform provider definitions separate while allowing the deployment entrypoint to select the appropriate configuration.

---

# 15. State and Bootstrap Initialization

SysMonitor uses Terraform remote state stored in S3.

The state infrastructure is bootstrapped before the main Terraform deployment.

The state bootstrap entrypoint is:

```bash
./init_tf.sh
```

From:

```text
sys_monitor/cloud/aws
```

run:

```bash
./init_tf.sh apply
```

The bootstrap creates the required state infrastructure for the selected deployment mode.

The state layout distinguishes the different purposes of the Terraform state.

The deployment uses:

```text
<env>/sys-monitor-local/tf-state
```

for local mode,

```text
<env>/sys-monitor-cross/tf-state
```

for cross-account mode,

and:

```text
<env>/sys-monitor-runtime/tf-state
```

for the main SysMonitor runtime infrastructure.

Verify that the state bootstrap completes successfully before continuing.

---

# 16. Verify Terraform State Bootstrap

After:

```bash
./init_tf.sh apply
```

verify the expected S3 state infrastructure exists.

The exact bucket name is derived from the configured AWS account:

```text
kubapp-sys-monitor-<ACCOUNT_ID>
```

The state bootstrap must complete successfully before the main runner is used.

If state initialization fails, fix the AWS permissions or configuration first.

Do not continue into the main deployment with an incomplete state bootstrap.

---

# 17. Cross-Account KubApp Prerequisite

Cross-account SysMonitor deployment depends on KubApp being prepared first.

KubApp must provide the cross-account integration required by SysMonitor, including:

```text
sys-monitor-cross-account-role
```

and the appropriate EKS access configuration where EKS is being accessed.

The SysMonitor deployment must not be treated as an isolated deployment in cross-account mode.

The dependency is:

```text
KubApp prepares cross-account access
                │
                ▼
SysMonitor identity exists
                │
                ▼
SysMonitor assumes KubApp role
                │
                ▼
SysMonitor accesses KubApp resources
```

This ordering prevents SysMonitor from attempting to use an AWS role or EKS access configuration that does not yet exist.

---

# 18. `store/status` Coordination

SysMonitor and KubApp use:

```text
sys_monitor/cloud/aws/store/status
```

as a deployment coordination mechanism.

This file is not an application health metric.

It communicates the availability state of the SysMonitor AWS deployment to the KubApp infrastructure layer.

The expected values are:

```text
active
```

or:

```text
inactive
```

## When SysMonitor is applied

After a successful main Terraform deployment:

```bash
./runner.sh apply
```

the runner updates:

```text
store/status
```

to:

```text
active
```

This indicates that the SysMonitor deployment has reached the state where its AWS-side identity and infrastructure are available for the KubApp cross-account integration.

## When SysMonitor is destroyed

After a successful:

```bash
./runner.sh destroy
```

the runner updates:

```text
store/status
```

to:

```text
inactive
```

This tells the KubApp infrastructure layer that the SysMonitor deployment is no longer available.

## Why this exists

KubApp uses this coordination state when determining whether cross-account SysMonitor resources should be created or used.

The purpose is to avoid creating or maintaining a cross-account dependency against a SysMonitor identity that is currently unavailable.

The relationship is therefore:

```text
SysMonitor runner
       │
       ├── apply  ──────► status = active
       │
       └── destroy ─────► status = inactive
                              │
                              ▼
                         KubApp IaC
                              │
                              └── decides whether
                                  cross-account resources
                                  should be enabled
```

`store/status` should therefore be treated as part of the deployment coordination contract between the two platforms.

It should not be interpreted as a replacement for service health checks, application monitoring, or infrastructure monitoring.

---

# 19. Deployment Entry Point

The primary AWS deployment entrypoint is:

```bash
./runner.sh
```

Run it from:

```text
sys_monitor/cloud/aws
```

The supported operations are:

```bash
./runner.sh plan
./runner.sh apply
./runner.sh destroy
```

Destroy can also be run non-interactively:

```bash
./runner.sh destroy -y
```

The runner determines the selected mode from:

```text
setup.env
```

and then performs the appropriate identity, Terraform, and runtime operations.

---

# 20. Recommended Deployment Order

A fresh deployment should follow this order.

## Step 1 — Prepare the workstation

Verify:

```bash
aws --version
terraform version
git --version
ssh -V
python3 --version
```

---

## Step 2 — Verify base AWS credentials

Run:

```bash
aws sts get-caller-identity
```

Confirm the expected identity.

---

## Step 3 — Verify the required AWS profiles

For the local profile:

```bash
aws sts get-caller-identity --profile <LOCAL_PROFILE>
```

For the cross profile:

```bash
aws sts get-caller-identity --profile sys-monitor
```

Do not continue until both required profiles behave as expected for the selected deployment mode.

---

## Step 4 — Verify GitHub access

Run:

```bash
ssh -T git@github.com
```

Confirm the repository can be accessed.

---

## Step 5 — Configure `setup.env`

Set:

```text
ENV
CLUSTER_MODE
AWS account IDs
AWS profiles
REGION
instance type
ACCESS_MODE
SYS_MONITOR_KEY_NAME
```

---

## Step 6 — Prepare and encrypt the secrets

Ensure the backend environment file exists at:

```text
sys_monitor/backend/.env
```

and the GitHub deploy key exists at:

```text
~/.ssh/sys_monitor_deploy
```

Use SOPS to prepare the encrypted secret files:

```bash
./runner.sh encrypt
```

The encrypted files are stored at:

```text
store/secrets/backend.env.enc
store/secrets/github-deploy-key.env.enc
```

Terraform provisions the corresponding SSM Parameter Store parameters during deployment:

```text
/sys-monitor/backend/env
/sys-monitor/github/deploy-key
```

The parameters do not need to be created manually.

---

## Step 7 — Prepare KubApp for cross-account mode

If:

```text
CLUSTER_MODE=cross
```

ensure KubApp has already prepared:

```text
sys-monitor-cross-account-role
```

and the required EKS access configuration.

---

## Step 8 — Bootstrap Terraform state

Run:

```bash
./init_tf.sh apply
```

Verify the state bootstrap succeeds.

---

## Step 9 — Bootstrap SysMonitor identity

The main runner performs the identity bootstrap automatically.

For a plan:

```bash
./runner.sh plan
```

For deployment:

```bash
./runner.sh apply
```

The identity layer is created before the main runtime infrastructure.

---

## Step 10 — Deploy the SysMonitor runtime

Run:

```bash
./runner.sh apply
```

The runner:

1. Selects the correct deployment mode.
2. Selects the appropriate AWS profile.
3. Bootstraps the required identity.
4. Activates the appropriate Terraform provider configuration.
5. Initializes Terraform against the remote state.
6. Validates the Terraform configuration.
7. Plans the infrastructure.
8. Applies the infrastructure.
9. Updates `store/status`.
10. Provisions the EC2 instance.
11. Bootstraps the instance.
12. Starts the SysMonitor services.

---

# 21. EC2 Access: SSM vs SSH

SysMonitor supports different access modes.

The recommended operational access method is:

```text
SSM
```

when SSM is enabled and available.

This avoids requiring an inbound SSH path to the instance.

For example:

```bash
aws ssm start-session \
  --target <INSTANCE_ID> \
  --profile <PROFILE>
```

The instance must have:

* SSM Agent
* network connectivity to SSM
* an appropriate EC2 IAM role
* the required SSM permissions

---

# 22. SSH Mode

SSH can be selected when direct SSH access is required.

When SSH mode is selected, the deployment expects the configured key pair:

```text
SYS_MONITOR_KEY_NAME
```

to correspond to an EC2 key pair.

The operator must have the matching private key locally.

For example:

```bash
ssh -i <PRIVATE_KEY> ec2-user@<PUBLIC_IP>
```

The private key must remain outside the repository and must have appropriate filesystem permissions:

```bash
chmod 600 <PRIVATE_KEY>
```

SSM and SSH are separate access mechanisms.

Choosing SSM does not require manually configuring an SSH connection for normal administration.

---

# 23. EC2 Bootstrap

The EC2 instance is initialized through:

```text
main/user_data.sh
```

The bootstrap installs and configures the runtime dependencies required by SysMonitor, including:

* Git
* Docker
* Docker Compose
* Docker Buildx
* kubectl
* SSM Agent
* supporting system utilities

It then:

1. retrieves the GitHub deploy key from SSM;
2. configures GitHub SSH access;
3. clones or updates the SysMonitor repository;
4. executes the edge setup;
5. generates the runtime `.env`;
6. starts the Docker Compose environment;
7. waits for required services;
8. configures the edge services;
9. configures TLS where enabled.

---

# 24. Runtime Role Model

The SysMonitor EC2 instance runs with:

```text
sys-monitor-ec2-role
```

This is the identity used by the host when interacting with AWS.

In cross-account mode, the application can use this identity to assume:

```text
sys-monitor-cross-account-role
```

in the KubApp account.

The application therefore does not require:

* manually exported temporary credentials;
* a manually created kubeconfig;
* manually executed `aws sts assume-role`;
* permanent AWS access keys embedded in the application.

The intended runtime flow is:

```text
SysMonitor application
        │
        ▼
EC2 instance credentials
        │
        ▼
sys-monitor-ec2-role
        │
        │ AssumeRole
        ▼
sys-monitor-cross-account-role
        │
        ▼
KubApp AWS resources
```

---

# 25. Kubernetes Access

The SysMonitor application does not depend on:

```bash
aws eks update-kubeconfig
```

being manually executed on the EC2 instance.

That command is useful for an operator who wants interactive `kubectl` access.

It is not the application's deployment mechanism.

For application operation, the GitOps service obtains:

1. the base AWS identity;
2. the configured target role when cross-account mode is enabled;
3. the EKS cluster endpoint;
4. an EKS authentication token;
5. Kubernetes API clients.

This allows the service to continue operating without an operator manually creating a kubeconfig.

---

# 26. Kubernetes Authorization

Successful AWS role assumption does not automatically grant Kubernetes permissions.

There are two requirements:

```text
AWS IAM authorization
+
EKS/Kubernetes authorization
```

For cross-account operation:

```text
sys-monitor-cross-account-role
```

must be:

1. allowed to perform the required AWS EKS operations;
2. registered with the EKS cluster;
3. granted the required Kubernetes permissions.

If the application can successfully assume the role but receives:

```text
403 Forbidden
```

from Kubernetes, inspect the EKS access entry and Kubernetes authorization rather than the AWS role assumption itself.

---

# 27. Verify the EC2 Deployment

After:

```bash
./runner.sh apply
```

Terraform should report:

```text
Apply complete!
```

The runner should also report:

```text
Status updated: .../store/status → active
```

Verify the status file:

```bash
cat store/status
```

Expected:

```text
active
```

---

# 28. Verify the Instance

Obtain the instance information from Terraform outputs or AWS:

```bash
aws ec2 describe-instances ...
```

Confirm that the instance is:

```text
running
```

and has the expected IAM instance profile.

---

# 29. Verify SSM

If using SSM:

```bash
aws ssm describe-instance-information
```

Confirm that the SysMonitor instance appears as a managed instance.

Then connect:

```bash
aws ssm start-session \
  --target <INSTANCE_ID>
```

---

# 30. Verify Docker Services

On the instance:

```bash
sudo docker ps
```

Confirm the expected SysMonitor services are running.

The GitOps service should be present, together with the other services defined by the Docker Compose deployment.

---

# 31. Verify GitHub Access from EC2

The instance should have the deployment key at:

```text
/root/.ssh/sys_monitor_deploy
```

and the repository should be available under:

```text
/opt/sys_monitor
```

Verify:

```bash
ls -la /opt/sys_monitor
```

---

# 32. Verify GitOps AWS Identity

The GitOps service should be able to report its AWS identity.

The expected cross-account flow is:

```text
sys-monitor-ec2-role
        │
        ▼
sys-monitor-cross-account-role
```

The service should not depend on manually exported AWS credentials.

If debugging the runtime identity, verify both identities:

```text
Base identity
Assumed identity
```

The base identity should correspond to the EC2 role.

The assumed identity should correspond to:

```text
sys-monitor-cross-account-role
```

when running in cross-account mode.

---

# 33. Verify EKS Access

For application-level verification, confirm that the GitOps service can:

* obtain the EKS endpoint;
* obtain an authentication token;
* initialize Kubernetes clients;
* list the resources it is authorized to inspect.

For example, the GitOps service should be able to perform its configured Argo CD resource queries.

A successful AWS `AssumeRole` alone is not sufficient.

The final verification must reach the Kubernetes API.

---

# 34. Verify Application Services

The deployment exposes the configured SysMonitor services through the environment's DNS/edge configuration.

Verify the configured endpoints from Terraform outputs.

Typical endpoints include:

```text
Grafana
Prometheus
GitHub
GitOps
Codebase
```

The exact hostnames are environment-specific.

Service health should be verified after the EC2 bootstrap has completed.

---

# 35. Deployment Verification Checklist

A deployment is considered successfully provisioned when all relevant checks pass.

### Workstation

```text
[ ] AWS CLI installed
[ ] Terraform installed
[ ] Git installed
[ ] SSH available
[ ] Base AWS credentials work
[ ] Required AWS profiles work
[ ] GitHub SSH access works
```

### AWS prerequisites

```text
[ ] Required AWS permissions exist
[ ] SOPS is installed and configured
[ ] Backend environment source file exists
[ ] GitHub deploy key source file exists
[ ] Encrypted backend environment file exists
[ ] Encrypted GitHub deploy-key file exists
[ ] Terraform provisions both SSM SecureString parameters
[ ] EC2 runtime role can retrieve both parameters
[ ] Cross-account role exists when required
[ ] EKS access is configured when required
```

### Terraform

```text
[ ] State bucket exists
[ ] Correct state key is selected
[ ] Terraform initialization succeeds
[ ] Terraform validation succeeds
[ ] Terraform apply succeeds
```

### Runtime

```text
[ ] EC2 instance is running
[ ] SSM is connected
[ ] Docker is running
[ ] SysMonitor containers are running
[ ] GitHub repository is available
[ ] Runtime configuration exists
```

### Cross-account

```text
[ ] EC2 base identity is correct
[ ] AssumeRole succeeds
[ ] Target identity is correct
[ ] EKS DescribeCluster succeeds
[ ] Kubernetes authorization succeeds
[ ] GitOps service initializes Kubernetes clients
```

### Coordination

```text
[ ] store/status exists
[ ] status is active after successful deployment
[ ] KubApp can consume the coordination state
```

---

# 36. Destroying the Environment

The main runtime environment can be destroyed with:

```bash
./runner.sh destroy
```

The command requests confirmation before destruction.

For non-interactive operation:

```bash
./runner.sh destroy -y
```

A successful destroy changes:

```text
store/status
```

to:

```text
inactive
```

This ensures KubApp does not treat the SysMonitor environment as currently available for cross-account integration.

---

# 37. Destroying Terraform State Infrastructure

State bootstrap is separate from the runtime deployment.

If the state infrastructure itself must be removed:

```bash
./init_tf.sh destroy
```

This should normally be treated as a separate administrative operation.

Do not destroy the state backend merely because the SysMonitor runtime is being temporarily removed.

The normal lifecycle is:

```text
runner.sh destroy
```

for runtime infrastructure, while the Terraform state infrastructure remains available for future deployments.

---

# 38. Local Development vs Production-Like Deployment

The deployment scripts are intended to make the AWS environment reproducible, but environment-specific configuration remains externalized through:

```text
setup.env
```

and AWS configuration.

Do not rely on undocumented local shell state such as:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

for normal operation.

The supported deployment path is through the configured AWS profiles and Terraform provider configuration.

Temporary credentials may be useful for troubleshooting, but they should not become a required deployment step.

---

# 39. Troubleshooting by Layer

When deployment fails, verify the layers in order.

## Layer 1 — Credentials

```bash
aws sts get-caller-identity
aws sts get-caller-identity --profile sys-monitor
```

If these fail, fix AWS authentication first.

## Layer 2 — Terraform

```bash
terraform version
terraform init
terraform validate
```

If these fail, fix Terraform configuration/state before continuing.

## Layer 3 — IAM

Verify:

```text
sys-monitor-ec2-role
sys-monitor-cross-account-role
```

and their trust/permission relationships.

## Layer 4 — EC2

Verify:

```text
instance running
IAM instance profile attached
SSM connected
```

## Layer 5 — Application

Verify:

```bash
sudo docker ps
sudo docker logs <container>
```

## Layer 6 — EKS

Verify:

```text
AssumeRole
DescribeCluster
EKS access entry
Kubernetes authorization
```

## Layer 7 — Application-level Kubernetes access

Verify that the GitOps service itself can initialize its Kubernetes clients and perform the operations required by SysMonitor.

This order prevents application-level symptoms from being mistaken for credential or infrastructure problems.

---

# 40. Operational Principle

SysMonitor is intended to operate without manual credential or Kubernetes setup on the deployed EC2 host.

The operator prepares the AWS identity and infrastructure once.

After deployment, the runtime should establish its own AWS and Kubernetes access through IAM and EKS authorization.

The intended model is:

```text
Operator
   │
   ├── configure AWS credentials
   ├── configure deployment
   └── run runner.sh
          │
          ▼
     Terraform
          │
          ▼
      AWS / EC2
          │
          ▼
   IAM instance role
          │
          ▼
    AssumeRole when required
          │
          ▼
   KubApp AWS resources
          │
          ▼
        EKS
          │
          ▼
   Kubernetes API
```

Manual commands such as:

```bash
aws sts assume-role
```

or:

```bash
aws eks update-kubeconfig
```

may be used for operator troubleshooting and interactive administration, but they are **not prerequisites for the SysMonitor application runtime**.

The application is expected to establish its own AWS and Kubernetes access using its configured identity chain.

---

# 41. Final Deployment Sequence

For a new environment, the complete sequence is:

```text
1. Install AWS CLI
        │
2. Configure AWS credentials
        │
3. Configure required AWS profiles
        │
4. Verify sys-monitor profile
        │
5. Install Terraform
        │
6. Configure Git / GitHub SSH
        │
7. Prepare and encrypt secrets with SOPS
        │
8. Configure setup.env
        │
9. Prepare KubApp cross-account resources
        │
10. Bootstrap Terraform state
        │
11. Run runner.sh plan
        │
12. Run runner.sh apply
        │
13. Verify store/status = active
        │
14. Verify EC2 / SSM
        │
15. Verify Docker services
        │
16. Verify runtime AWS identity
        │
17. Verify AssumeRole
        │
18. Verify EKS access
        │
19. Verify GitOps Kubernetes access
        │
20. Verify SysMonitor services
```

A deployment should not be considered complete merely because Terraform reports `Apply complete`.
The final verification must establish that the deployed SysMonitor runtime can obtain its AWS identity, assume the required role when operating cross-account, authenticate to EKS, and perform the Kubernetes operations required by the gitops-exporter application.
