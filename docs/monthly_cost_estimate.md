# KUBAPP Monthly Cost Estimate

The figures are estimates, not fixed monthly charges. Actual costs depend on resource capacity, workload volume, deployment activity, storage consumption, API usage, and the AWS pricing applicable to the region.

## 1. Estimated Infrastructure Baseline

The following figures are based on the Infracost generated report for `iac/infra`, and the Terraform configuration under `iac/database`.

| Service | Configuration | Estimated Monthly Cost (USD) |
|---|---|---:|
| Amazon EKS | Kubernetes control plane | $73.00 |
| Amazon EC2 – App Nodes | 2 × t3.large, including modeled EBS storage | $127.47 |
| Amazon EC2 – System Nodes | 2 × t3.large, including modeled EBS storage | $127.47 |
| NAT Gateway | 2 gateways, fixed hourly charges | $65.70 |
| AWS Fargate | Modeled workload estimate; actual usage needs verification | $32.80 |
| **Infrastructure Subtotal** | | **$426.44** |
| Amazon RDS for PostgreSQL | Multi-AZ, db.t3.micro, 20 GB gp3 storage | $30.88 |
| **Estimated Baseline Total** | | **$457.32** |

**Important:** Fargate costs are based on the CPU and memory resources consumed by running pods. The $32.80 figure is the quantity modeled by Infracost and should not be treated as a confirmed recurring charge without checking actual Fargate workload consumption.

The EC2 estimates already include the EBS storage modeled for the worker nodes.

The RDS estimate uses approximately $26.28 for Multi-AZ database compute and $4.60 for 20 GB of gp3 storage. The configured 100 GB maximum storage is an autoscaling limit, not the initial billable allocation. Additional backup storage and CPU credit charges are not included.

## 2. Additional Usage-Dependent Costs

Some services are provisioned or available in the infrastructure, but their actual monthly costs depend on consumption.

| Service | What Determines the Cost |
|---|---|
| Amazon EFS | Storage consumed, throughput, and applicable access charges. |
| Amazon S3 | Stored data, requests, retrieval, and data transfer. Includes Terraform state storage. |
| Amazon CloudWatch | Log ingestion, retention, storage, and query volume. |
| NAT Gateway Processing | Data processed through each gateway, in addition to its hourly charge. |
| Route 53 | Hosted zones and DNS query volume. |
| Data Transfer | Traffic between services, availability zones, regions, and external networks. |
| Application Load Balancer | Number of active load balancers, usage capacity units, and processed traffic. |

These costs are not fully represented in the $457.32 baseline. In particular, the Infracost report does not provide enough usage information to calculate reliable monthly totals for these services.

## 3. Database Infrastructure

KUBAPP maintains database infrastructure separately under `iac/database`.

The database configuration includes Amazon RDS for PostgreSQL 16, a `db.t3.micro` instance, Multi-AZ deployment, encrypted gp3 storage, 20 GB initial allocation, up to 100 GB autoscaling storage, and 7-day automated backup retention.

The database estimate covers the modeled RDS compute and initial storage allocation. Additional backup consumption, CPU credits, and data transfer may increase the actual cost.

The database infrastructure also uses private subnets, security groups, and VPC peering. These resources do not introduce separate fixed hourly charges, although network traffic may incur charges.

## 4. External and AI Services

KUBAPP also depends on services that are not fully represented in the AWS infrastructure estimate.

| Service | Cost Consideration |
|---|---|
| Docker Hub | Depends on the subscription plan, storage, and usage limits. |
| OpenAI API | Depends on the selected model and token consumption. |
| Google AI API | Depends on the selected model, API pricing, and request volume. |
| Ollama | No per-token API charge when running locally; infrastructure and compute resources still have costs. |

KUBAPP supports multiple AI providers. Supporting additional providers does not automatically increase costs. Charges arise from actual API consumption or the infrastructure required to run local models.

## 5. Factors That Can Increase Monthly Costs

The baseline is based on a particular infrastructure configuration. Actual costs can increase as KUBAPP grows.

Examples include:

- Deploying more applications that require additional worker capacity.
- Scaling EC2 node groups or increasing instance sizes.
- Provisioning additional NAT Gateways.
- Creating additional Application Load Balancers.
- Increasing RDS capacity, storage, or database availability requirements.
- Increasing CloudWatch log ingestion and retention.
- Storing more application data, container images, and backups.
- Increasing network traffic and cross-availability-zone data transfer.
- Increasing AI API requests and token consumption.

More applications do not necessarily mean proportionally higher infrastructure costs. Multiple applications can share existing cluster capacity and platform resources until additional capacity or separate resources are required.

## 6. Estimation Scope and Limitations

The supplied Infracost reports cover:

| Terraform Directory | Detected Resources | Infracost Monthly Estimate |
|---|---:|---:|
| `iac/infra` | 94 | $426.44 |
| `iac/k8s` | 3 | $0.00 |
| `iac/manifests` | 0 | $0.00 |

The three resources detected in `iac/k8s` are EKS add-ons for which Infracost did not assign a direct price. The manifests report detected no Terraform resources.

The $0.00 figures do not mean that these components or the workloads they manage are free. They mean that the reports did not identify separately priced resources in those directories.

The RDS estimate is calculated separately from the Terraform configuration and variables under `iac/database`; it is not part of the supplied Infracost reports.

## 7. Estimated Monthly Total

| Cost Category | Monthly Estimate |
|---|---:|
| `iac/infra` infrastructure baseline | $426.44 |
| `iac/database` RDS baseline | $30.88 |
| Additional usage-dependent services | Not yet quantified |
| Docker Hub and AI services | Not included |
| **Estimated Infrastructure Baseline** | **$457.32** |

**Current estimated infrastructure baseline: $457.32/month.**

This is a reference estimate for the infrastructure configuration captured in the October 9, 2026 report and the supplied database configuration. It is not the complete monthly operating cost of KUBAPP. Actual expenditure will vary with workload size, resource scaling, service consumption, and external service usage.
