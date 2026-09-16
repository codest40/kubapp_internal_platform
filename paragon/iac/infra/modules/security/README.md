# Security

The `security/` module creates the AWS Security Groups defined by the `sg-prep/` module.

## Purpose

KUBAPP separates security policy from security group creation.

The `sg-prep/` module defines **what traffic should be allowed**, while this module translates those definitions into actual AWS Security Groups and rules.

## What It Creates

| Resource                               | Purpose                                         |
| -------------------------------------- | ----------------------------------------------- |
| Security Groups                        | Provide network boundaries for KUBAPP workloads |
| Ingress rules                          | Control allowed inbound traffic                 |
| Egress rules                           | Control allowed outbound traffic                |
| Security-group-to-security-group rules | Allow traffic between specific workload layers  |
| CIDR-based rules                       | Allow traffic from defined network ranges       |

Example:

```text id="p0xq1n"
sg-prep
   │
   │ Security rules
   ▼
security
   │
   ├── Ingress SG
   ├── EC2 App SG
   ├── Fargate App SG
   └── Cache SG
```

Rules can reference either another Security Group or a CIDR range.

## Why KUBAPP Uses It

KUBAPP may run workloads across EC2 and Fargate, so network access should be explicitly controlled between workload layers.

For example:

```text id="6g1v5s"
Internet
   │
   ▼
Ingress SG
   │
   ├──► EC2 App SG
   │
   └──► Fargate App SG
              │
              ▼
          Cache SG
```

This provides a clearer security boundary than allowing broad network access between workloads.

## Module Inputs

| Input            | Purpose                                            |
| ---------------- | -------------------------------------------------- |
| `vpc_id`         | VPC where Security Groups are created              |
| `sg_definitions` | Security group and rule definitions from `sg-prep` |
| `name_prefix`    | Consistent resource naming                         |
| `cluster_name`   | Associates resources with the KUBAPP cluster       |
| `tags`           | Common resource tags                               |

## Outputs

| Output   | Purpose                                               |
| -------- | ----------------------------------------------------- |
| `sg_ids` | Map of Security Group names to AWS Security Group IDs |

## KUBAPP Role
This module forms part of KUBAPP's **network security layer**.
It turns the platform's declared security policies into enforceable AWS network controls.
