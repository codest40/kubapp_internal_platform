# IAM IRSA

The `iam-irsa/` module provides AWS IAM roles for Kubernetes workloads and platform components using **IAM Roles for Service Accounts (IRSA)**.

## Purpose

KUBAPP workloads should not need broad AWS permissions through the EC2 worker node role.

Instead, Kubernetes service accounts can assume dedicated IAM roles through the EKS OIDC provider. This gives individual workloads access to only the AWS services they require.

## What It Creates

| Component                    | Purpose                                      |
| ---------------------------- | -------------------------------------------- |
| AWS Load Balancer Controller | Provides AWS load balancing permissions      |
| External DNS                 | Provides Route 53 DNS management permissions |
| EBS CSI Driver               | Provides EBS volume management permissions   |
| EFS CSI Driver               | Provides EFS management permissions          |
| Fluent Bit                   | Provides CloudWatch Logs permissions         |
| Application pods             | Provides application-specific AWS access     |

Example:

```text id="j7x2p9"
                    EKS OIDC
                       │
                       ▼
              Kubernetes Service Account
                       │
                       ▼
                  IAM Role (IRSA)
                       │
             ┌─────────┼─────────┐
             ▼         ▼         ▼
          AWS APIs   S3/Logs   Route 53
```

Each role is restricted to specific Kubernetes service accounts through the EKS OIDC trust relationship.

## Why KUBAPP Uses It

IRSA keeps AWS permissions at the **workload identity level** rather than giving every Kubernetes workload access through the node IAM role.

This provides:

* Workload-level AWS permissions
* Reduced reliance on node credentials
* Better separation of platform components
* Secure access to AWS services
* Easier permission auditing and management

For example, External DNS can modify Route 53 records without giving application pods Route 53 permissions.

## Managed Components

| Component                | AWS Access                                |
| ------------------------ | ----------------------------------------- |
| Load Balancer Controller | AWS load balancing resources              |
| External DNS             | Route 53 DNS records                      |
| EBS CSI Driver           | EBS volume operations                     |
| EFS CSI Driver           | EFS operations                            |
| Fluent Bit               | CloudWatch Logs                           |
| Application Pods         | Read-only CloudWatch, Logs, and S3 access |

## Module Inputs

| Input               | Purpose                                   |
| ------------------- | ----------------------------------------- |
| `cluster_name`      | Used to name IAM resources                |
| `oidc_provider_arn` | EKS OIDC provider used for federation     |
| `oidc_provider_url` | Used to restrict service-account identity |
| `hosted_zone_id`    | Route 53 zone used by External DNS        |
| `account_id`        | AWS account identification                |
| `region`            | AWS region                                |
| `tags`              | Common resource tags                      |

## Outputs

| Output                   | Purpose                       |
| ------------------------ | ----------------------------- |
| `lb_controller_role_arn` | Load Balancer Controller role |
| `external_dns_role_arn`  | External DNS role             |
| `ebs_csi_irsa_arn`       | EBS CSI Driver role           |
| `efs_role_arn`           | EFS CSI Driver role           |
| `fluentbit_role_arn`     | Fluent Bit role               |
| `app_pods_role_arn`      | Application workload role     |

## KUBAPP Role

This module forms the **Kubernetes-to-AWS identity layer** of KUBAPP.

It allows Kubernetes workloads and platform controllers to securely access AWS services without embedding AWS credentials in applications or giving workloads unnecessary permissions.
