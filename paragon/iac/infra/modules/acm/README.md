# ACM

This module provisions and validates the **AWS Certificate Manager (ACM)** certificate used by KUBAPP for secure HTTPS traffic.

## Purpose

KUBAPP exposes applications through Kubernetes Ingress and an AWS Load Balancer. HTTPS requires a trusted TLS certificate, so this module automates certificate provisioning and **DNS-based validation through Route 53**.

## What It Creates

| Resource                    | Purpose                                 |
| --------------------------- | --------------------------------------- |
| ACM certificate             | Provides TLS for the KUBAPP domain      |
| Wildcard certificate        | Secures application subdomains          |
| Route 53 validation records | Proves domain ownership to ACM          |
| Certificate validation      | Automatically validates the certificate |

The certificate covers:

```text
example.com
*.example.com
```

This allows KUBAPP to securely serve both the main domain and application subdomains.

## Why KUBAPP Uses It

KUBAPP manages certificates through Terraform instead of creating them manually in AWS.

This provides:

* Automated HTTPS provisioning
* DNS-based certificate validation
* Infrastructure-as-Code management
* Support for application subdomains
* Reproducible deployments across environments

## Flow

```text
Terraform
    │
    ▼
ACM Certificate
    │
    ▼
Route 53 DNS Validation
    │
    ▼
Validated Certificate
    │
    ▼
Kubernetes Ingress / AWS Load Balancer
    │
    ▼
HTTPS Applications
```

## Module Inputs

| Input     | Purpose                                      |
| --------- | -------------------------------------------- |
| `domain`  | Main domain used for the certificate         |
| `zone_id` | Route 53 hosted zone used for DNS validation |
| `tags`    | Common resource tags                         |

## Outputs

| Output         | Purpose                              |
| -------------- | ------------------------------------ |
| `acm_cert_arn` | ARN of the validated ACM certificate |

## KUBAPP Role

The `acm/` module is part of KUBAPP's **routing and security layer**.

It provides the TLS certificate required to securely expose applications over HTTPS, while Terraform and Route 53 handle the provisioning and validation automatically.
