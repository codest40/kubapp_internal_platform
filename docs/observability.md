# Observability

## Design Philosophy: Broad Visibility, Clear Ownership

KUBAPP approaches observability as a layered responsibility. The objective is to maintain visibility across infrastructure, Kubernetes workloads, application delivery, and the internal components that make up the platform itself.

Rather than forcing every monitoring responsibility into a single system, KUBAPP uses specialized tools to observe different parts of the environment. Each layer has a distinct responsibility, and together they provide a broader understanding of the platform's health.

The goal is to have eyes almost everywhere, with clear ownership of monitoring responsibilities and enough visibility to investigate failures across system boundaries.

## Observability Layers

### 1. Kubernetes and Infrastructure Resources

**Tools:** Prometheus and Grafana

Prometheus collects metrics from Kubernetes and its monitored resources, while Grafana provides dashboards for examining their health and performance.

This layer provides visibility into the cluster resources supporting deployed workloads. It helps identify resource pressure, abnormal utilization, and infrastructure conditions that may affect application behavior.

### 2. Kubernetes Control Plane

**Managed by:** AWS through Amazon EKS

KUBAPP uses Amazon EKS, where AWS operates and maintains the Kubernetes control plane. So KUBAPP does not manage the underlying control-plane machines. AWS exposes monitoring interfaces and diagnostic information that can provide visibility into control-plane health and activity.

While KUBAPP can use the monitoring information AWS exposes to investigate relevant issues, Kubapp does not currently observe this because the operational requirements and value of observing the Control-plane is not justified at this stage.

### 3. Application Delivery and GitOps Reconciliation

**Tool:** Argo CD

Argo CD monitors the relationship between the desired application configuration in Git and the state of applications deployed in Kubernetes.

Its responsibility is to provide visibility into application synchronization, deployment health, and GitOps reconciliation. It helps identify situations where the deployed state differs from the desired state or an application is not healthy according to Argo CD's health assessment.

This layer focuses on delivery and reconciliation rather than resource utilization or detailed application behavior.

### 4. Internal Platform and Application Health

**Tool:** SysMonitor

SysMonitor provides visibility into the internal health of KUBAPP and the systems involved in its operation.

Its monitoring responsibilities include:

- **Deployed applications:** Application-level health and operational metrics.
- **Database:** Database health and relevant application-facing metrics.
- **GitOps:** Metrics describing the state and activity of the GitOps environment.
- **GitHub:** Metrics collected through the GitHub exporter.
- **Codebase:** Metrics describing the monitored codebase and its analysis.

SysMonitor uses different monitoring approaches depending on the system being observed.

**Metrics-based monitoring** covers areas such as GitOps, GitHub, and codebase analysis, where metrics describe state, activity, or changes.

**Application-based monitoring** covers deployed applications and the database, focusing on the health and behavior of running systems.

Through these capabilities, SysMonitor extends visibility beyond cluster resources and deployment status to the applications and internal services that support KUBAPP's operation.


## Correlation Across Observability Layers

An incident can produce signals across several observability layers, with each system revealing a different aspect of the problem.

For example, an application failure might appear as an unhealthy application in Argo CD, abnormal resource utilization in Kubernetes monitoring, and application-level errors in SysMonitor.

These observations are complementary. Correlating them helps establish relationships between symptoms, confirm findings from different perspectives, and narrow down possible causes. Resource pressure occurring alongside application errors may point toward an infrastructure-related problem, while healthy infrastructure metrics alongside failing application checks may direct the investigation toward the application or its dependencies.

The value comes from combining these different perspectives. No single monitoring layer necessarily provides the full explanation for an incident, but their observations together can provide stronger diagnostic evidence and a clearer understanding of what happened.

## Guiding Principle

Each layer should provide meaningful visibility into its area of responsibility while contributing evidence that can be correlated with observations from other layers. Monitoring capabilities should evolve as the platform grows, addressing new visibility gaps and operational requirements.

The objective is to understand the state of KUBAPP, detect failures, and investigate their causes using complementary evidence from across the platform.
