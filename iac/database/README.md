# KUBAPP Database Infrastructure

The `iac/database` layer provisions and manages the database infrastructure used by KUBAPP applications.

It is separate from the main KUBAPP infrastructure so that database resources can have their own lifecycle, state, security boundaries, and deployment model.

## Purpose

This layer provides:

* PostgreSQL database infrastructure
* Database networking
* Database security controls
* Database credentials and secret integration
* Local and cross-account deployment support

The database itself is managed by Terraform. Applications consume the database through the connection details and credentials provided to them.

## Deployment Modes

The database layer supports two deployment modes.

### Local

The database runs inside the KUBAPP account and uses the existing KUBAPP VPC and private subnets.

The database is reachable from workloads through the KUBAPP network.

### Cross-account

The database runs in a separate AWS account.

The database account creates its own network and connects to the KUBAPP VPC through VPC peering.

This keeps the database infrastructure separate while still allowing KUBAPP workloads to use it.

## Security

Database access is controlled at two levels:

1. **Network access** determines whether a workload can reach PostgreSQL.
2. **Database credentials** determine whether it can authenticate.

The `db_access` security boundary is used by the platform for database-related network access. The current EC2 path uses the EC2 node security group for network reachability, while database credentials remain the application authorization mechanism.

More detailed security and access behavior is documented in `COMPONENTS.md`.

## Secrets

Database credentials are managed using SOPS.

The database infrastructure provides the information needed by KUBAPP to configure applications that require database access.

Plaintext credentials are not intended to be committed to the repository.

## Relationship with KUBAPP

`iac/database` depends on information provided by the main KUBAPP infrastructure, such as:

* VPC information
* Subnets
* Security-group information
* Account information

The database layer can also expose information needed by KUBAPP and its applications.

This keeps the main infrastructure and database infrastructure separate while allowing them to work together.

## Operational Model

The general flow is:

```text
KUBAPP Infrastructure
        ↓
Database Infrastructure
        ↓
PostgreSQL
        ↓
Database connection information
        ↓
KUBAPP application
```

The database layer manages the infrastructure required for the database.

Application initialization, queries, and application-level database behavior remain the responsibility of the application.

## Components

The individual Terraform resources, scripts, security boundaries, deployment modes, and supporting concepts are described in:

`COMPONENTS.md`
