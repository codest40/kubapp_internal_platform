# Network

The `network/` module provisions the core AWS networking infrastructure used by KUBAPP.

## Purpose

KUBAPP runs its workloads inside an isolated VPC. This module creates the network foundation required for EKS, applications, load balancers, and supporting AWS services.

## What It Creates

| Resource                        | Purpose                                             |
| ------------------------------- | --------------------------------------------------- |
| VPC                             | Provides the isolated network for KUBAPP            |
| Internet Gateway                | Provides internet connectivity for public resources |
| Public subnets                  | Host internet-facing infrastructure                 |
| Private subnets                 | Host EKS and application workloads                  |
| NAT Gateways                    | Provide controlled outbound internet access         |
| Elastic IPs                     | Provide stable public IPs for NAT Gateways          |
| Public and private route tables | Control network traffic paths                       |
| VPC Flow Logs                   | Provide visibility into VPC network traffic         |

The design uses one public and one private subnet per Availability Zone.

```text
                    Internet
                       │
                       ▼
                Internet Gateway
                       │
              ┌────────┴────────┐
              ▼                 ▼
         Public Subnet      Public Subnet
             AZ-1               AZ-2
              │                   │
          NAT Gateway          NAT Gateway
              │                   │
              ▼                   ▼
         Private Subnet      Private Subnet
             AZ-1               AZ-2
              │                   │
              └────────┬──────────┘
                       ▼
                  EKS / Workloads
```

## Why KUBAPP Uses It

KUBAPP keeps application workloads in **private subnets** while using public subnets for internet-facing infrastructure such as NAT Gateways and load balancers.

This provides:

* Network isolation for workloads
* Controlled outbound internet access through NAT
* Multi-AZ networking
* Public and private routing separation
* A foundation for EKS networking
* VPC-level traffic visibility through Flow Logs

Each Availability Zone has its own NAT Gateway and private route table, avoiding a single NAT Gateway becoming a cross-AZ dependency.

## Module Inputs

| Input              | Purpose                                     |
| ------------------ | ------------------------------------------- |
| `vpc_cidr`         | VPC CIDR range                              |
| `azs`              | Availability Zones used by the VPC          |
| `public_subnets`   | CIDRs for public subnets                    |
| `private_subnets`  | CIDRs for private subnets                   |
| `vpc_flow_log_arn` | CloudWatch destination for VPC Flow Logs    |
| `name`             | Resource naming prefix                      |
| `cluster_name`     | Associates networking resources with KUBAPP |
| `tags`             | Common resource tags                        |

## Outputs

| Output               | Purpose                                      |
| -------------------- | -------------------------------------------- |
| `vpc_id`             | VPC ID consumed by other modules             |
| `public_subnet_ids`  | Public subnet IDs                            |
| `private_subnet_ids` | Private subnet IDs used by EKS and workloads |
| `nat_public_ip`      | Public IP addresses assigned to NAT Gateways |

## KUBAPP Role

This module provides the **network foundation of KUBAPP**. Other infrastructure components, including EKS, security groups, EFS, and load-balancing infrastructure, depend on this network layer.
