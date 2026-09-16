# IAM Core

The `iam-core/` module creates the core AWS IAM roles required by KUBAPP's EKS cluster, worker nodes, Fargate workloads, and system monitoring.

## Purpose

KUBAPP separates the permissions required by different platform components instead of using a single shared AWS identity.

This module provides the **base IAM layer** for the platform. Workload-specific Kubernetes identities are handled separately by the `iam-irsa/` module.

## What It Creates

| Resource                      | Purpose                                                             |
| ----------------------------- | ------------------------------------------------------------------- |
| EKS cluster IAM role          | Provides AWS permissions required by the EKS control plane          |
| EC2 worker node IAM role      | Provides AWS permissions required by EKS worker nodes               |
| Fargate pod execution role    | Allows Fargate pods to interact with required AWS services          |
| System monitoring EC2 role    | Provides AWS permissions required by the system monitoring instance |
| EC2 instance profile          | Attaches the monitoring IAM role to the EC2 instance                |
| Cross-account monitoring role | Enables authorized monitoring access across AWS accounts            |

Example:

```text id="m9q5qf"
                    IAM Core
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   EKS Cluster     EC2 Nodes       Fargate
      Role            Role        Execution Role
        │
        └──────────────┐
                       ▼
                System Monitor
                       │
                       ▼
             Cross-Account Access
```

## Why KUBAPP Uses It

Different components of KUBAPP require different levels of AWS access.

Separating these roles provides:

* Clear permission boundaries
* Least-privilege-oriented access
* Secure EKS operation
* AWS access for EC2 and Fargate
* Systems monitoring access
* Cross-account monitoring capabilities

For example, worker nodes receive permissions required to operate as EKS nodes, while the system monitoring instance receives permissions specifically required for monitoring and Kubernetes access.

## Module Inputs

| Input          | Purpose                                   |
| -------------- | ----------------------------------------- |
| `cluster_name` | Used to identify and name IAM resources   |
| `account_id`   | Used for cross-account role configuration |
| `tags`         | Common resource tags                      |

## Outputs

| Output                               | Purpose                                              |
| ------------------------------------ | ---------------------------------------------------- |
| `eks_cluster_role_arn`               | IAM role used by the EKS control plane               |
| `node_group_role_arn`                | IAM role used by EC2 worker nodes                    |
| `fargate_role_arn`                   | Fargate pod execution role                           |
| `sys_monitor_ec2_role_arn`           | IAM role for the system monitoring EC2 instance      |
| `sys_monitor_instance_profile_name`  | Instance profile attached to the monitoring instance |
| `sys_monitor_eks_cross_account_role` | Cross-account monitoring role ARN                    |

## KUBAPP Role

This module forms the **base identity and access layer** of KUBAPP.

It establishes the AWS identities required for the platform to operate, while `iam-irsa/` provides more specific AWS permissions to Kubernetes service accounts.
