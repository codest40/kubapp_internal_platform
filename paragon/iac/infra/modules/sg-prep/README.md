# SG Prep

The `sg-prep/` module defines the security group rules that KUBAPP will use for its workloads.

## Purpose

Rather than hardcoding security group rules directly inside the security module, KUBAPP separates **security group definition** from **security group creation**.

This module prepares the desired security model and passes it to the `security/` module.

## What It Defines

| Security Group                | Purpose                                            |
| ----------------------------- | -------------------------------------------------- |
| Ingress / External Traffic    | Controls traffic entering KUBAPP                   |
| EC2 Application Workloads     | Controls network access to EC2-based workloads     |
| Fargate Application Workloads | Controls network access to Fargate-based workloads |
| Application Cache             | Controls access to application cache services      |

Example:

```text
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

Rules can allow traffic based on:

* Source security groups
* CIDR ranges
* Application ports
* Protocols

## Why KUBAPP Uses It

KUBAPP may run different workloads on different compute types. Their network access requirements should therefore be defined explicitly rather than using broad, shared security groups.

Separating the definitions from the actual AWS resources makes the security model easier to:

* Read
* Modify
* Extend
* Reuse
* Review

Custom security group definitions can also be supplied when an application requires additional networking rules.

## Module Inputs

| Input                                           | Purpose                              |
| ----------------------------------------------- | ------------------------------------ |
| `from_port_ec2_app` / `to_port_ec2_app`         | EC2 application port                 |
| `from_port_fargate_app` / `to_port_fargate_app` | Fargate application port             |
| `from_port_cache_app` / `to_port_cache_app`     | Cache port                           |
| `custom_sg_definitions`                         | Additional or custom security groups |
| `private_subnets_cidr`                          | Private subnet network ranges        |
| `tags`                                          | Common resource tags                 |

## Outputs

| Output           | Purpose                                                                |
| ---------------- | ---------------------------------------------------------------------- |
| `sg_definitions` | Complete security group definitions consumed by the `security/` module |

## KUBAPP Role

This module represents the **network security policy layer** of KUBAPP.

It defines **what traffic should be allowed**; the `security/` module is responsible for **creating those rules in AWS**.
