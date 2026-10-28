# Summary of what kubapp does

## 1. Infrastructure Provisioning

- KUBAPP uses Terraform to establish and manage the AWS infrastructure that supports its application delivery platform. This includes initial account and identity setup, networking, EKS, IAM, security controls, DNS, certificates, storage, logging, and database infrastructure.
- Infrastructure is organized into reusable modules and environment-specific configurations, with support for separate database infrastructure and cross-account networking. Kubernetes configuration and platform manifests build on this foundation.

### The infrastructure layer covers:

- Bootstrap and identity: Initial AWS and GitHub setup, including an OIDC-only bootstrap path.
- Core cloud infrastructure: Networking, EKS, IAM, security groups, ACM certificates, and supporting AWS resources.
- Database infrastructure: Database provisioning and cross-account networking.
- DNS management: Route 53 and DNS infrastructure.
- Storage and logging: EFS and logging integrations.
- Kubernetes configuration: Cluster configuration, manifests, and platform alerts.
- Infrastructure organization: Reusable Terraform modules, environment-specific configurations, and managed infrastructure state.


## 2. Kubernetes + GitOps Platform

KUBAPP uses Kubernetes as its application runtime and Argo CD to manage deployments through GitOps. Application definitions, Helm charts, environment-specific values, ingress configuration, and deployment state are organized in Git to support consistent, traceable application delivery.

### The Kubernetes and GitOps layer covers:
- **GitOps reconciliation:** Argo CD applications and configuration for synchronizing the desired state in Git with the Kubernetes cluster.
- **Reusable Helm charts:** Shared charts for applications, ingress, and PostgreSQL.
- **Environment management:** Environment-specific application values and ingress configuration.
- **Application and service registry:** Registry state used to organize application and service information.
- **Secret management:** SOPS-managed secrets for GitOps configuration.
- **Platform state:** State used to track platform build and deployment processes.


## 3. Observability and Platform Visibility

KUBAPP includes an extensive observability system designed to provide visibility into the platform, deployed applications, and supporting infrastructure. It combines metrics, monitoring integrations, codebase analysis, and a customized operational interface to help users understand application and platform state, investigate issues, and manage their deployments.

### The observability layer covers:
- **Infrastructure monitoring:** Visibility into AWS resources and supporting cloud infrastructure.
- **Application and platform metrics:** Prometheus-based monitoring and Grafana integrations.
- **Codebase discovery and analysis:** Tools for discovering and analyzing application codebases.
- **Integration metrics:** Exporters for GitHub and GitOps-related information.
- **Unified operational interface:** A customized interface for inspecting deployed applications and KUBAPP components, presenting relevant status and operational information in an accessible way.
- **Independent monitoring infrastructure:** Dedicated infrastructure and configuration for the `sys_monitor` system.


## 4. Codebase and Execution Logic

KUBAPP's execution layer contains the automation and control logic that coordinates application discovery, CI, infrastructure and GitOps operations, platform state management, and maintenance tasks. It connects the platform's individual components through reusable scripts and workflows, keeping operational logic organized and maintainable.

### The execution layer covers:
- **Application discovery and CI:** Application detection, configuration validation, dependency handling, build execution, and CI checks.
- **Platform and AWS cleanup:** Automation for cleaning up platform resources and AWS infrastructure.
- **Drift detection:** Detection of differences between the declared and actual GitOps or Terraform state.
- **Shared automation:** Reusable helpers supporting platform operations.
- **GitHub integration:** Automation for GitHub-related workflows and operations.
- **GitOps operations:** Scripts for managing GitOps workflows and Argo CD interactions.
- **Platform registry and reconciliation:** Logic for maintaining platform registry information and coordinating reconciliation.
- **Execution documentation:** Documentation for understanding and maintaining the platform's automation.



## 5. Workflow Orchestration

KUBAPP uses GitHub Actions to orchestrate CI/CD and platform automation workflows. These workflows connect repository events, infrastructure operations, application delivery, and supporting maintenance tasks, coordinating the execution of platform logic.

### The workflow layer covers:
- **CI/CD orchestration:** Workflows that coordinate application validation and delivery.
- **Platform automation:** Workflows for infrastructure and other platform operations.
- **Workflow documentation:** Documentation covering workflow behavior and operational procedures.


## 6. Application Onboarding

KUBAPP provides a dedicated workspace for application services, separating application source code and configuration from the platform's infrastructure and operational logic. This allows applications to be onboarded through a consistent structure while KUBAPP handles the relevant validation, build, and delivery processes.
Application workspaces are organized under `docker/`:

```text
docker/
├── <application>/
├── ...
```

### The onboarding layer supports:
- **Application organization:** Separate workspaces for individual applications and services.
- **Application discovery and validation:** Detection and validation of application configuration and runtime requirements.
- **Standardized delivery:** Integration with KUBAPP's CI/CD and GitOps workflows.
- **Independent application development:** Keeping application-specific files separate from the platform's core infrastructure and automation.


## 7. Setup and Platform Preparation

KUBAPP provides setup and preparation automation to help users configure the required cloud infrastructure, repository integrations, credentials, and tooling. Additional scripts prepare changes for delivery by validating platform configuration, protecting secrets, checking application definitions, and coordinating Git operations before changes are pushed.

### The setup and preparation layer covers:
- **Initial platform setup:** Coordinating AWS bootstrap, repository discovery, GitHub configuration, and Terraform backend preparation.
- **Identity and integration configuration:** Setting up GitHub Actions variables and secrets, AWS access through configured roles, and GitHub App integration.
- **Secret preparation:** Installing and configuring SOPS and AGE tooling, preparing encryption keys, and integrating secret handling into the activation workflow.
- **Tooling and cost estimation:** Preparing required command-line tools and configuring Infracost integration.
- **Pre-push activation:** Preparing Git state, validating configuration, encrypting secrets, checking GitOps configuration, and optionally validating applications before finalizing Git operations.
- **Application configuration validation:** Checking application CI definitions, runtime configuration, file paths, commands, required secrets, and health-check settings before delivery.
- **Operational guidance:** Providing setup instructions and workflow documentation to help users configure and operate KUBAPP.

