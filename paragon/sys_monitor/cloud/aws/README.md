# AWS

The `cloud/aws/` directory contains the AWS infrastructure and deployment automation for SysMonitor.
It provisions the AWS resources required to run SysMonitor and provides scripts for bootstrapping, deploying, configuring, and managing the environment.

## Responsibilities

The AWS layer handles:

* Terraform infrastructure provisioning.
* Terraform remote state storage.
* VPC and networking.
* EC2 compute resources.
* Security groups.
* IAM roles and instance profiles.
* Cross-account AWS access.
* Route 53 DNS records.
* EC2 instance bootstrapping.
* SysMonitor environment configuration.
* Application deployment to EC2.
* Docker-based service startup.

## Structure

```text
aws/
├── boot/
├── backend.tf
├── create_env.sh
├── local.tf
├── local_roles.tf
├── main.tf
├── outputs.tf
├── providers.tf
├── route53.tf
├── start.sh
├── start_letsencrypt.sh
├── user_data.sh
└── variables.tf
```

## Main Components

| Component              | Purpose                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------- |
| `boot/`                | Creates and manages the S3 bucket used for Terraform remote state.                                            |
| `main.tf`              | Defines the main AWS infrastructure, including VPC, subnet, security group, EC2, and Elastic IP.              |
| `providers.tf`         | Configures Terraform and the AWS providers, including the cross-account provider.                             |
| `backend.tf`           | Configures the Terraform S3 remote-state backend.                                                             |
| `local.tf`             | Defines local Terraform values used by the AWS deployment.                                                    |
| `local_roles.tf`       | Creates the IAM role and instance profile used by the SysMonitor EC2 instance.                                |
| `route53.tf`           | Configures Route 53 DNS records.                                                                              |
| `variables.tf`         | Defines AWS deployment inputs and configuration values.                                                       |
| `outputs.tf`           | Exposes useful deployment information such as the public IP and service URLs.                                 |
| `user_data.sh`         | Bootstraps a new EC2 instance with required system tools and dependencies.                                    |
| `create_env.sh`        | Generates the runtime environment configuration for SysMonitor.                                               |
| `start.sh`             | Main AWS deployment script that provisions infrastructure, synchronizes the project, and starts the services. |
| `start_letsencrypt.sh` | Alternative deployment flow that also configures Nginx and HTTPS using Let's Encrypt.                         |

## Deployment Model

The current AWS deployment uses:

* **EC2** as the SysMonitor host.
* **VPC** for network isolation.
* **Public subnet** for the EC2 instance.
* **Security Group** for network access control.
* **Elastic IP** for a stable public address.
* **IAM instance profile** for AWS API access from EC2.
* **S3** for Terraform remote state.
* **Route 53** for DNS where enabled.
* **Docker Compose** to run the SysMonitor services on the EC2 host.

Terraform is responsible for infrastructure, while the deployment scripts handle instance preparation, code synchronization, environment configuration, and application startup.

## Deployment Modes

The AWS configuration supports different operating modes, including:

* **Local account mode** — SysMonitor and the target AWS resources operate within the same account.
* **Cross-account mode** — the EC2 instance assumes a dedicated IAM role in another AWS account when access to resources such as EKS is required.

The selected mode affects AWS provider configuration, IAM permissions, and environment generation.

## Terraform State

The AWS infrastructure uses an S3 bucket for remote Terraform state.

The bootstrap configuration under `boot/` creates the state bucket before the main AWS infrastructure is managed.

The main infrastructure then uses that bucket through `backend.tf`.

This separates **Terraform state infrastructure** from the **SysMonitor infrastructure** that consumes the state backend.
