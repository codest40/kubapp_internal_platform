# Docker

The `docker/` directory contains the application layer of KUBAPP.

This is **not a major platform infrastructure component**. It acts as the application store where developers place services after development. KUBAPP discovers applications here and manages those that contain a valid `Dockerfile`.

The purpose of this directory is to provide a predictable structure for building and preparing applications for deployment.

---

## Application Structure

Each application directory name must end with **_app** to be detected
Then it follows a standardized structure:

```text
service_app/
├── Dockerfile
├── kubapp.yml
├── application source code
└── runtime dependencies
```

The platform uses this structure to discover and understand applications without requiring each service to implement its own deployment process.

A service can therefore be:

- built
- validated
- containerized
- deployed
- monitored
- scaled
- troubleshot

using the same platform workflow.

---

## `kubapp.yml`

Each service can define a lightweight `kubapp.yml` file containing deployment metadata.

This allows KUBAPP to understand how the application should be deployed without hardcoding application-specific logic into CI/CD pipelines or Kubernetes manifests.
The metadata can describe:

- compute type
- application port
- health endpoints
- storage requirements
- runtime features
- deployment environment settings

Example:

```yaml
name: transaction-api

compute: ec2

port: 3000

health:
  path: /health

storage:
  ephemeral: true
```

The exact schema is defined by the KUBAPP deployment automation.

---

## Compute Selection

KUBAPP supports multiple compute models.

Applications can run on:

- EC2-backed Kubernetes nodes
- AWS Fargate

The choice depends on the workload.

### EC2

EC2-backed nodes are appropriate when an application requires greater control over:

- runtime configuration
- security
- networking
- storage
- node-level behavior
- workload isolation

For example, transaction-processing workloads may require the additional control provided by EC2-backed nodes.

### Fargate

Fargate is suitable for workloads that are primarily:

- user-facing
- stateless
- lightweight
- independently scalable

This allows KUBAPP to use different compute models without changing the application's basic deployment workflow.

---

## Default Configuration

A `kubapp.yml` file is **not a Must**.

If an application contains a valid `Dockerfile` but does not provide a `kubapp.yml`, KUBAPP will still attempt to manage the application using the platform's default configuration.

This allows applications to be onboarded with minimal configuration.

```text
Valid Dockerfile
       |
       v
Application discovered
       |
       v
kubapp.yml exists?
    /          \
  Yes           No
   |             |
   v             v
Custom         Platform
Config         Defaults
   |             |
   +------+------+
          |
          v
      KUBAPP manages
        application
```

However, relying on the default configuration may not be appropriate for every workload.
Applications with specific runtime requirements may require explicit configuration to operate efficiently.

For example, an application may need:

- a specific compute model
- non-default resource limits
- custom health endpoints
- specific ports
- persistent storage
- special security settings
- workload-specific scheduling
- environment-specific configuration

In these cases, providing a `kubapp.yml` allows the application to communicate its requirements to the platform.

## Runtime Configuration

Applications are designed to be Kubernetes-ready from the beginning.

Deployment metadata can describe runtime requirements such as:

- readiness and liveness endpoints
- container ports
- ephemeral storage
- container security settings
- environment-specific configuration
- optional Prometheus `ServiceMonitor` integration

The platform converts these requirements into the appropriate deployment configuration.

---

## Secrets Management

Sensitive configuration is **not stored as plaintext** in the repository.

KUBAPP uses **SOPS** to encrypt sensitive configuration.

The general workflow is:

```text
Developer
    |
    v
Encrypted secret
    |
    v
Git repository
    |
    v
Authorized deployment workflow
    |
    v
Decrypt
    |
    v
Kubernetes
```

Secrets remain version-controlled while their plaintext values remain protected.

Decryption should only occur in authorized deployment environments.

---

## Local Development

The directory also supports local development using Docker Compose.

This provides a way to:

- build application containers
- run services locally
- test service dependencies
- validate configuration
- troubleshoot applications

before they enter the Kubernetes deployment workflow.

Typical flow:

```text
Developer
    |
    v
Application development
    |
    v
Docker Compose
    |
    v
Local validation
    |
    v
Docker image
    |
    v
CI/CD
    |
    v
KUBAPP deployment
    |
    v
Kubernetes
```

---

## Platform Boundary

The `docker/` directory is intentionally kept lightweight.

KUBAPP does not require developers to understand the internal platform implementation in order to package an application.

Developers primarily provide:

1. Application source code
2. `Dockerfile`
3. `kubapp.yml`
4. Required runtime configuration

The platform is responsible for the deployment mechanics.

This separation keeps application development independent from the underlying infrastructure while giving the platform enough metadata to automate deployment consistently.

---

## Application-to-Platform Flow

```text
                    Developer
                        |
                        v
                Application Source
                        |
                        v
             +---------------------+
             |      docker/        |
             |                     |
             | Dockerfile          |
             | kubapp.yml          |
             | Application Code    |
             +----------+----------+
                        |
                        v
                  CI/CD Pipeline
                        |
                        v
                  Container Image
                        |
                        v
                KUBAPP Platform
                        |
              +---------+---------+
              |                   |
              v                   v
           EC2 Nodes           Fargate
              |                   |
              +---------+---------+
                        |
                        v
                    Kubernetes
```

---

## Design Goal
The goal of the `docker/` layer is **standardization without unnecessary abstraction**.
Applications remain independent while following a predictable contract that allows KUBAPP to discover, build, configure, and deploy them consistently.
