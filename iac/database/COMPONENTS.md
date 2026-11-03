# Database Components

## 1. Terraform Configuration

The Terraform configuration provisions and manages the database infrastructure in AWS.

It supports local and cross-account deployment modes, allowing the database to operate either within the KUBAPP account or in a separate AWS account.

### Database

The database is an Amazon RDS PostgreSQL instance. Its configuration controls:

- PostgreSQL version and instance size.
- Allocated storage and storage encryption.
- Multi-AZ deployment.
- Automated backups and retention.
- Deletion protection.

### Database Network

The database runs in private subnets and supports both local and cross-account network configurations.

The selected network configuration determines how the database connects to the KUBAPP VPC.

### Database Security Group

The database security group controls inbound access to PostgreSQL on port `5432`.

For the current local configuration, access is permitted from the EKS cluster security group because EC2-backed workloads use the node network path.

The `db_access` security group provides a separate access boundary for database workloads and supports future workload-level isolation.

Database access depends on two conditions:

- Network reachability to the database.
- Valid database credentials.

### Remote State

The database configuration reads selected values from the KUBAPP Terraform remote state, including:

- VPC ID and CIDR.
- Private subnet IDs.
- Database access security group ID.
- EKS cluster security group ID.

This allows the database infrastructure to integrate with KUBAPP without duplicating its network configuration.

## 2. Secret Management

Database credentials are protected using SOPS.

The database secret configuration supplies the master username and password to Terraform during database provisioning.

Database connection information is also integrated into KUBAPP's secret configuration flow so applications can obtain the credentials and connection details required to connect.

## 3. Supporting Scripts

The scripts automate database infrastructure setup, deployment, configuration, and secret handling.

| Script | Responsibility |
|---|---|
| `runner.sh` | Main database infrastructure runner. Handles initialization, planning, applying, and destroying Terraform resources. It loads the protected setup configuration, selects the deployment mode, prepares required variables and secrets, and coordinates the Terraform workflow. |
| `init.sh` | Bootstraps the Terraform state backend and, where required, the cross-account role infrastructure. It must be run when setting up the backend and its supporting access resources. |
| `manage_network.sh` | Selects the local or cross-account network configuration. It activates the corresponding Terraform network file and variable file while removing the files belonging to the other mode. |
| `helpers.sh` | Provides shared functions used by the database scripts, including AWS identity checks, directory validation, Terraform initialization and validation, SOPS encryption and decryption, and Terraform variable preparation. |
| `secrets.sh` | Decrypts the database credential file with SOPS and exports the master username and password as Terraform variables. |

### Stored Configuration

The `store/` directory contains configuration files used by the database infrastructure.

It includes the stored Terraform network configurations, optional mode-specific variable files, and encrypted secret files. The scripts select or decrypt these files when required rather than keeping all deployment configurations active simultaneously.

### Assume Config

assume/ directory manages the IAM roles and permissions required for the database infrastructure to operate across AWS accounts.

It creates the `db-terraform-role` in the database account, allowing authorized IAM users and the configured GitHub Actions role to assume it and manage database infrastructure.

The role also grants permission to assume the `db-cross-account-role` in the KUBAPP account, enabling the database infrastructure to access the required KUBAPP resources across account boundaries.

The directory includes a separate bootstrap configuration for preparing the Terraform state backend used by the assume-role infrastructure.

This separates the permissions required to provision and manage the database infrastructure from the credentials used to initiate deployment.

## 4. Application Integration

The database infrastructure provides the database service and the connection information applications need to use it.

**Infrastructure ownership includes:**
- Database provisioning and configuration.
- Network connectivity and security boundaries.
- Storage, availability, and backups.
- Database infrastructure credentials.

**Application ownership includes:**
- Database schemas and migrations.
- Queries and application-level data operations.
- Connection handling and application data behaviour.

This separation allows KUBAPP to manage the database infrastructure while applications retain control over how they use the database.
