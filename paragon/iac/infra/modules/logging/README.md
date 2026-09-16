# Logging

The `logging/` module provisions the AWS CloudWatch Log Groups used by KUBAPP for centralized logging.

## Purpose

KUBAPP needs a consistent place to store application, security, Kubernetes, and network logs. This module creates and configures the required CloudWatch Log Groups instead of relying on manually created AWS resources.

## What It Creates

| Resource                    | Purpose                               |
| --------------------------- | ------------------------------------- |
| Application log groups      | Store application and workload logs   |
| Audit/security log groups   | Store security and audit-related logs |
| EKS cluster log groups      | Store Kubernetes control plane logs   |
| VPC Flow Log groups         | Store network traffic logs            |
| Log retention configuration | Controls how long logs are retained   |

Example:

```text
KUBAPP
  │
  ├── Applications ──────► CloudWatch
  ├── EKS Cluster Logs ──► CloudWatch
  ├── Audit Logs ────────► CloudWatch
  └── VPC Flow Logs ─────► CloudWatch
```

## Why KUBAPP Uses It

Centralizing logs makes the platform easier to operate, monitor, and troubleshoot.

The module provides:

* Centralized AWS logging
* Environment-specific log groups
* Configurable retention
* Consistent resource tagging
* Infrastructure-as-Code management

This also allows other KUBAPP components, such as Fluent Bit and VPC Flow Logs, to use predefined log destinations.

## Module Inputs

| Input          | Purpose                                      |
| -------------- | -------------------------------------------- |
| `log_groups`   | Defines the log groups and retention periods |
| `cluster_name` | Associates logs with the EKS cluster         |
| `name_prefix`  | Provides consistent resource naming          |
| `tags`         | Common resource tags                         |

## Outputs

| Output            | Purpose                                   |
| ----------------- | ----------------------------------------- |
| `log_group_names` | Map of created CloudWatch Log Group names |
| `log_group_arns`  | Map of created CloudWatch Log Group ARNs  |

## KUBAPP Role

This module forms part of KUBAPP's **observability layer**, providing centralized and consistently managed logging for the platform and its workloads.
