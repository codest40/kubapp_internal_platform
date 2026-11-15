# SysMonitor

SysMonitor is the internal system-awareness and observability layer of KubApp.

The key idea is:

> **Kubernetes tells us what is happening to the platform externally. Argocd tells us the deployment state between git and kubernetes. SysMonitor is intended to tell us what is happening inside the KubApp system itself.**

SysMonitor is designed to observe and analyze changes, activity, configuration, infrastructure, and operational state that may not be visible through Kubernetes, ArgoCD, or Terraform alone.

It covers areas such as:

- Monitor Deployed Apps and databse health 
- Internal system's components activity like CI, CD, Gitops, Kubernetes monitoring layer
- Infrastructure and deployment state.
- GitHub activity.
- GitOps activity.
- Files being created, modified, or deleted.
- Scripts and configuration changes.
- Prometheus metrics and Grafana dashboards.
- Eventually, correlation between changes, processes, users, events, and system state.
- To a certain degree, external changes that affect the system.

## Project Structure

The root directory contains the major components of SysMonitor.

| Directory/File | Purpose |
|---|---|
| 'backend/ | backend services and APIs that provide monitoring data to consumers. |
| 'frontend/ | User interface for viewing system, application, and database monitoring information. |
| `cloud/` | Cloud infrastructure and AWS deployment automation. |
| `codebase/` | Codebase discovery, validation, drift, architecture, security, and metrics analysis. |
| `exporters/` | Exporters that collect and expose system-specific metrics and events. |
| `observability/` | Prometheus and Grafana configuration for collecting and visualizing metrics. |
| `docker-compose.yml` | Defines the local containerized SysMonitor stack. |
| `README.md` | High-level documentation and entry point for the SysMonitor project. |

## High-Level Flow

SysMonitor is organized around several layers:

1. **Cloud**
   - SysMonitor needs to run inside a server.
   - This section provisions the server.
   - Currently includes AWS/EC2 provisioning and deployment automation.

2. **Codebase**
   - Examines the KubApp repository files.
   - Builds an inventory and checks file integrity.
   - Detects drift, security issues, syntax and architectural problems, and validation issues.
   - Produces evidence and Prometheus metrics.

3. **Exporters**
   - Collect operational events and expose them as metrics.
   - Includes GitHub and GitOps-related exporters.

4. **Observability**
   - Prometheus collects metrics from the different exporters.
   - Grafana provides dashboards for viewing the collected data.

5. **Docker Compose**
   - Connects the major SysMonitor services into a runnable local stack.

6. **Backend**
   - The backend provides the data and API functionality consumed by the frontend and other clients.
   - The running application includes application health information and database connectivity monitoring. Its responsibilities and interfaces are documented separately in backend/README.md.

7. **Frontend**
   - The frontend presents monitoring information through a unified interface.
   - It currently displays application health information and database monitoring results obtained through the backend. Its responsibilities and integration with the backend are documented in frontend/README.md

## What SysMonitor Is Intended to Provide

For example:
- Are deployed apps healthy or not (the same experience final users get from apps) ?
- Is the database operating as expected?
- Is the codebase changing unexpectedly?
- Has infrastructure configuration drifted?
- Are security-sensitive files exposed?
- Are repository structures violating expected architectural boundaries?
- Are GitHub workflows succeeding?
- Are selected GitOps operations healthy?
- What metrics describe the current state of the system?
- Can changes in the repository or infrastructure be correlated with operational events?

This makes SysMonitor a complementary layer to the existing KubApp platform.

