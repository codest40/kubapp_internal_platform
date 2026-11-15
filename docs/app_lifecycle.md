# KUBAPP APPLICATION LIFECYCLE SUMMARY

KUBAPP is primarily designed as a heterogeneous application onboarding and delivery platform. It accommodates applications built with different runtimes, tools, and development approaches while maintaining centralized control over validation, security, build execution, and delivery. By default, KUBAPP treats developer-supplied code and executable inputs as potentially malicious, applying controlled execution boundaries and layered security checks throughout the application lifecycle.

The infrastructure provisioned through `iac/` using Terraform is assumed to be available before application onboarding begins. This provides the cloud infrastructure, identity, networking, Kubernetes, and supporting services required by the platform.

### 1. Application Discovery and Qualification

Applications are organized independently under `docker/`. KUBAPP discovers eligible applications through the presence of a `ci.yml` file at the root of each application directory.

Each discovered application is validated against the platform's expected configuration requirements. These include a non-empty Dockerfile, required manifest files, and valid CI configuration. Optional application data files, such as `kubapp.yml` and encrypted secret files, are also recognized where applicable.

Only qualified applications proceed to CI processing. Their required configuration and supporting data are collected, and isolated execution environments are prepared for their individual build workflows.

### 2. Application CI and Layered Security Validation

Qualified applications enter CI concurrently, with each component processed in a separate thread and its own execution context.

The workflow applies multiple security layers:

- **Command policy validation:** Developer-supplied commands and tools are checked against platform restrictions. Unapproved operations, including potentially dangerous utilities and unrestricted shell execution, are restricted.
- **AI-assisted security assessment:** Applicable developer-supplied test scripts, commands, modules, and other executable artifacts are analyzed through the configured AI assessment providers. Each assessment returns a decision value (`0` or `1`) alongside its reasoning. KUBAPP evaluates the result and retains authority over whether execution may proceed.
- **Source-code analysis:** KUBAPP integrates SonarQube to examine application source code for potential bugs, security-sensitive patterns, and maintainability issues. This provides a platform-managed analysis layer, including for applications whose developers have not defined their own application-specific CI tests.
- **Restricted application execution:** Developer-defined linting, application security checks, and unit tests execute inside a restricted environment designed to limit unnecessary access to the host and platform.

Required checks must satisfy their configured conditions before an application can proceed.

### 3. Image Building and Publication

After successful application validation and testing, the application source and required build data are collected for image construction.

Docker image building and inspection take place in a separate, less-restricted container environment with the permissions required for image operations. This remains distinct from the restricted environment used for developer-controlled application commands.

Following successful image construction and inspection, KUBAPP collects additional build information, including Software Bills of Materials (SBOMs) and other application metadata. These records are saved as platform state, and the resulting application images are published to Docker Hub for downstream delivery.

### 4. Platform Build and Deployment Data Preparation

The platform build stage collects successful application build results and organizes the information required by downstream deployment workflows.

It retrieves the published image references and associated application metadata, then generates the deployment data required for each qualified application. These outputs are stored under `gitops/state/`, establishing a defined interface between application CI and the GitOps deployment stages.

### 5. GitOps Deployment and Kubernetes Reconciliation

Deployment is initiated through a separate, manually triggered workflow.

Applications are discovered through the GitOps registry under `gitops/registry`. For each eligible application, the deployment workflow collects its prepared deployment data and updates the relevant Helm templates and application configuration under `gitops/envs/apps/`.

Argo CD observes the changes in Git and reconciles the declared desired state with the Kubernetes API. Kubernetes then schedules, runs, and continuously manages the deployed application workloads according to their specifications.

### 6. Application Management, Monitoring, and Platform Visibility

KUBAPP combines Kubernetes-native monitoring with an independent monitoring and alerting system to provide visibility across the application lifecycle.

Prometheus and Grafana provide monitoring coverage for Kubernetes resources and supporting infrastructure. Argo CD provides visibility into GitOps synchronization and application deployment health.

Beyond these responsibilities, the external `sys_monitor/` system provides additional operational awareness across KUBAPP and its deployed applications. Its monitoring scope includes:

- **Application health:** Visibility into the operational health of deployed applications beyond basic workload and deployment status.
- **Database operations:** Monitoring of the KUBAPP database and its operational condition.
- **GitHub activity:** Visibility into relevant repository events and integration activity.
- **GitOps metrics:** Monitoring of important GitOps operational metrics not already adequately covered by Kubernetes monitoring or the Argo CD application interface.
- **Platform codebase integrity:** Analysis of KUBAPP's own codebase, including integrity statistics across its files and scripts.
- **Platform component health:** Awareness of the operational state of major internal and external platform components.

This separation avoids unnecessarily duplicating monitoring responsibilities while extending visibility into areas that Kubernetes and Argo CD do not independently cover.

Together, these stages establish a delivery lifecycle in which KUBAPP discovers heterogeneous applications, validates and securely processes their inputs, builds and publishes application images, prepares deployment data, coordinates GitOps delivery, and maintains operational visibility across both deployed applications and the platform itself.
