# Database Infrastructure Components

This document explains the main components and concepts used by `iac/database`.

## Terraform Configuration

The database infrastructure is managed independently from the main KUBAPP infrastructure.

Terraform is responsible for creating and maintaining the database, networking, security groups, and supporting AWS resources.

The configuration supports both local and cross-account deployment.

## Deployment Mode

The database configuration determines whether it is running in the KUBAPP account or in a separate database account.

### Local Mode

Local mode uses the existing KUBAPP network.

The database is placed in KUBAPP private subnets and uses the existing VPC.

### Cross-account Mode

Cross-account mode creates the database network in the database account.

This includes:

* A database VPC
* Private subnets
* Database subnet groups
* VPC peering with KUBAPP
* Routes between the two VPCs

The database account therefore owns its database network while KUBAPP provides the application side of the connection.

## RDS PostgreSQL

The database is provided by Amazon RDS for PostgreSQL.

The database configuration controls properties such as:

* PostgreSQL version
* Instance size
* Storage
* Multi-AZ deployment
* Encryption
* Backups
* Deletion behavior

Applications do not manage the database server itself.

## Database Network

The database is placed in private subnets and is not intended to be directly exposed to the public internet.

The network layout differs by deployment mode, but the database remains reachable through private AWS networking.

## Database Security Group

The database security group controls network access to PostgreSQL.

PostgreSQL uses port `5432`.

The allowed source depends on the deployment mode and the workload networking model.

For the current local EC2 path, the database trusts the EKS cluster security group because EC2 workloads use the node network path.

The existing `db_access` boundary remains part of the design for workload-level database access and future stronger isolation.

## `db_access`

`db_access` represents the platform's database access boundary.

Today, it is primarily used as a network boundary for workloads that use database services.

The current authorization model is intentionally simple:

```text
Network reachability
        +
Database credentials
        =
Database access
```

This leaves room for the platform to introduce stronger workload-level controls later without changing the application's basic database contract.

## Database Credentials

Applications that use the database receive database credentials through the KUBAPP secret flow.

Having network access to PostgreSQL does not by itself provide database access. The application also needs valid database credentials.

This separates:

* **Can the workload reach PostgreSQL?**
* **Can the workload authenticate to PostgreSQL?**

## SOPS

SOPS is used to protect database secrets.

Encrypted secret configuration can be stored with the project while keeping database passwords protected.

The database infrastructure does not expose plaintext credentials as part of its normal repository configuration.

## Secret Integration

Database information produced by the infrastructure is passed into the KUBAPP secret flow.

Supporting scripts update the database-related configuration consumed by applications.

The database layer provides the infrastructure information; KUBAPP handles making that information available to workloads.

## Remote State

The database layer reads selected information from the KUBAPP infrastructure Terraform state.

Examples include:

* VPC ID
* VPC CIDR
* Private subnet IDs
* Database access security-group ID
* EKS cluster security-group ID

This allows the database layer to integrate with existing infrastructure without recreating resources it does not own.

## Cross-account Access

Cross-account deployments require controlled access between the database account and KUBAPP.

The database infrastructure can use roles created for the database account to perform the required Terraform operations and establish the required network relationship.

The database account owns its resources while KUBAPP retains ownership of its own infrastructure.

## Supporting Scripts

Scripts around the database infrastructure handle tasks that are not Terraform resources themselves.

Examples include:

* Updating database connection information
* Updating the KUBAPP database secret configuration
* Creating Kubernetes secrets from the protected configuration

These scripts connect the infrastructure layer to the GitOps and application layers.

## Application Integration

An application declares that it needs database access.

KUBAPP then provides the required database connection information and credentials.

The application remains responsible for:

* Creating or migrating its schema
* Running queries
* Managing its connection pool
* Handling application-level database errors
* Defining its own database behavior

The database infrastructure does not manage application-specific database logic.

## Ownership Boundary

The database layer owns:

```text
AWS database infrastructure
Network
Security groups
Database availability
Storage
Backups
Database infrastructure credentials
```

The application owns:

```text
Schema
Queries
Migrations
Connection usage
Application data behavior
```

KUBAPP connects these two sides without taking ownership of application database logic.
