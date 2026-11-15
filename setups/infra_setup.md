# KUBAPP Infrastructure Environments Setup Guide

## 1. Overview

KUBAPP, its database infrastructure, and sys_monitor can be deployed together or independently.

Most KUBAPP setup operations are already automated through dedicated scripts. The main consideration when setting up the complete environment is the order in which the infrastructure components are initialized and connected.

The setup process has three major stages:

1. Initialize the individual infrastructure components.
2. Establish the database and sys_monitor infrastructure.
3. Enable cross-component state access and complete the integrations.

## 2. Important Configuration Rule

Whenever changes are made to `setup.env`, run:

```bash
./runner.sh encrypt
```

This ensures the encrypted configuration reflects the latest values used by the infrastructure scripts.

## 3. Understanding the Network Modes

### KUBAPP Infrastructure

KUBAPP uses `10.0.0.0/16` as its primary network boundary.

Its operating mode is primarily determined by the VPC CIDR relative to this network boundary and the AWS account in which KUBAPP infrastructure is deployed.

When initializing KUBAPP infrastructure from scratch, avoid enabling account-mode integrations and remote state consumption prematurely.

The database and sys_monitor must first establish their infrastructure before KUBAPP completes the cross-component integrations.

### Database Infrastructure

The database supports two network modes:

| Mode | VPC CIDR |
|---|---|
| Local mode | `10.0.0.0/16` |
| Cross mode | `10.20.0.0/16` |

The database operates in cross mode when its VPC CIDR differs from KUBAPP's local network boundary.

### sys_monitor

sys_monitor can operate in a separate AWS account from KUBAPP. In that arrangement, it uses cross-account access to communicate with KUBAPP infrastructure.

## 4. Recommended Deployment Sequence

### Stage 1: Initialize KUBAPP Infrastructure

In `iac/infra`, initially configure the integrations for database and sys_monitor without enabling remote state consumption.

The relevant settings should initially be disabled:

- Account-mode integrations.
- Database remote-state reading.
- sys_monitor remote-state reading.

Apply the KUBAPP infrastructure.

### Stage 2: Initialize Database and sys_monitor

Once the initial KUBAPP infrastructure exists, proceed with the other components.

**Database**

Initialize and apply the database infrastructure using its dedicated setup procedures.

**sys_monitor**

Navigate to:

```text
sys_monitor/cloud/aws/
```

Initialize and apply its Terraform state using:

```bash
./init_tf.sh
```

Then apply the infrastructure using the corresponding runner procedure.

### Stage 3: Configure Cross-Account Roles

If the database runs in cross mode, establish the necessary IAM roles before configuring sys_monitor's cross-account access.

This ordering matters because sys_monitor's role-assumption configuration may depend on roles created by the database infrastructure.

When sys_monitor operates in cross mode, it also depends on KUBAPP-created IAM resources.

The relevant KUBAPP resources include:

```text
aws_iam_instance_profile.sys_monitor
aws_iam_role.kubapp_reads_sys_monitor_state
aws_iam_role.sys_monitor
```

These resources must exist before the corresponding sys_monitor role-assumption configuration can be completed.

### Stage 4: Complete Cross-Component Integration

After the database and sys_monitor infrastructure have been established, return to `iac/infra`.

Enable the required state-reading and account-mode configurations.

The following settings control the combined setup. iac/infra/terraform.tfvars:

```hcl
enable_db_local_account         = true
db_enabled                      = true
allow_kubapp_read_db_state      = true
allow_kubapp_read_sys_monitor_state = true
enable_sys_monitor_cross_account = true
sys_monitor_enabled             = true
```

Apply the updated infrastructure configuration.

This completes the integration stage, allowing KUBAPP to establish the required connections, including VPC peering and other cross-component configurations.

## 5. Recommended Account Arrangement

The simplest recommended arrangement is:

| Component | AWS Account |
|---|---|
| KUBAPP infrastructure | Account A |
| Database | Account A |
| sys_monitor | Account B |

This arrangement allows the database to operate in either local or cross mode relative to KUBAPP, while sys_monitor operates in cross-account mode.

The final network configuration determines the database's operating mode.
