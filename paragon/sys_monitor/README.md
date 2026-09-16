# SysMonitor

SysMonitor is the internal system-awareness and observability layer of KubApp.

The key idea is:

> **Kubernetes tells us what is happening to the platform externally. SysMonitor is intended to tell us what is happening inside the KubApp system itself.**

SysMonitor is designed to observe and analyze changes, activity, configuration, infrastructure, and operational state that may not be visible through Kubernetes, ArgoCD, or Terraform alone.

It covers areas such as:

- Files being created, modified, or deleted.
- Scripts and configuration changes.
- Unexpected changes to project files.
- Infrastructure and deployment state.
- GitHub activity.
- GitOps activity.
- Prometheus metrics and Grafana dashboards.
- Internal system activity.
- Eventually, correlation between changes, processes, users, events, and system state.
- To a certain degree, external changes that affect the system.

## Project Structure

The root directory contains the major components of SysMonitor.

| Directory/File | Purpose |
|---|---|
| `cloud/` | Cloud infrastructure and AWS deployment automation. |
| `codebase/` | Codebase discovery, validation, drift, architecture, security, and metrics analysis. |
| `exporters/` | Exporters that collect and expose system-specific metrics and events. |
| `observability/` | Prometheus and Grafana configuration for collecting and visualizing metrics. |
| `docker-compose.yml` | Defines the local containerized SysMonitor stack. |
| `README.md` | High-level documentation and entry point for the SysMonitor project. |

## High-Level Flow

SysMonitor is organized around several layers:

1. **Cloud**
   - Provides the infrastructure required to run SysMonitor.
   - Currently includes AWS/EC2 provisioning and deployment automation.

2. **Codebase**
   - Examines the KubApp repository itself.
   - Builds an inventory of the repository.
   - Detects drift, security issues, architectural problems, and validation issues.
   - Produces evidence and Prometheus metrics.

3. **Exporters**
   - Collect operational events and expose them as metrics.
   - Includes GitHub and GitOps-related exporters.

4. **Observability**
   - Prometheus collects metrics from the different exporters.
   - Grafana provides dashboards for viewing the collected data.

5. **Docker Compose**
   - Connects the major SysMonitor services into a runnable local stack.

6. **Future AI Analysis Implementation**

## What SysMonitor Is Intended to Provide

The purpose of SysMonitor is NOT simply to monitor application availability.
It is intended to provide **awareness of the system itself**.

For example:
- Is the codebase changing unexpectedly?
- Has infrastructure configuration drifted?
- Are security-sensitive files exposed?
- Are repository structures violating expected architectural boundaries?
- Are GitHub workflows succeeding?
- Are GitOps operations healthy?
- What metrics describe the current state of the system?
- Can changes in the repository or infrastructure be correlated with operational events?

This makes SysMonitor a complementary layer to the existing KubApp platform.

