# KUBAPP — GitOps Architecture

## Overview

KUBAPP uses GitOps to manage the desired state of applications and supporting Kubernetes resources. Rather than treating deployment as a series of manual cluster operations, KUBAPP keeps deployment configuration in Git and uses Argo CD to reconcile that configuration with the running cluster.

The approach combines a service registry, environment-specific application values, reusable Helm charts, and Argo CD ApplicationSets to establish a consistent deployment model across applications.

## How KUBAPP Handles GitOps

KUBAPP separates application build processes from deployment management. CI handles application validation and image creation, while the GitOps layer defines how those images should run in Kubernetes.

The deployment configuration brings together application definitions, image references, runtime settings, and supporting resources. Argo CD then uses this configuration to synchronize the desired state with the cluster.

This separation allows application delivery to evolve without tightly coupling application build logic to Kubernetes resource definitions.

## Architectural Approach

### Declarative Application Delivery

KUBAPP uses Git as the source of truth for managed application configuration. Argo CD continuously reconciles the declared state with the Kubernetes environment, reducing the need for manual deployment operations.

### Reusable Deployment Templates

Helm provides reusable templates for application workloads, ingress resources, and PostgreSQL deployments. Applications share common deployment definitions while supplying their own runtime configuration through environment-specific values.

This avoids maintaining an entirely separate set of Kubernetes manifests for every application.

### Application Discovery and Management

Argo CD ApplicationSets generate application resources from the configured application directories. This allows KUBAPP to follow a repeatable onboarding pattern rather than requiring a manually maintained Argo CD Application definition for every service.

The service registry provides a separate place for application and build-related metadata used by the platform's delivery workflow.

### Environment-Specific Configuration

KUBAPP separates application configuration by environment. This allows workload settings, image references, resource requirements, and other runtime options to be managed without embedding every variation into a shared Helm chart.

The same deployment model can therefore accommodate multiple applications while preserving application-specific configuration.

### Integrated Infrastructure and Operations

The GitOps layer connects application deployment with the infrastructure and operational services that support it. This includes ingress configuration for traffic routing, SOPS and age for encrypted secrets, and ServiceMonitor resources for integrating supported workloads with Prometheus.

These integrations allow deployment configuration to describe not only how an application runs, but also how it is exposed, configured, and monitored.

## Technologies Used

- **Argo CD:** Reconciles Git-defined configuration with the Kubernetes cluster.
- **Argo CD ApplicationSets:** Generate and manage applications from configured application directories.
- **Helm:** Provides reusable templates for Kubernetes workloads and supporting resources.
- **Kubernetes:** Runs the deployed applications and supporting services.
- **SOPS and age:** Protect sensitive configuration through encryption before it is committed to Git.
- **Prometheus integration:** Enables supported applications to expose metrics through ServiceMonitor resources.
- **AWS Load Balancer Controller integration:** Supports ingress-based application exposure through AWS load balancers.

## Design Outcome

KUBAPP's GitOps model establishes a clear separation between building applications, defining their runtime configuration, and reconciling their deployment state.

By combining declarative configuration, reusable Helm charts, application discovery, and automated reconciliation, the platform provides a consistent way to manage Kubernetes application delivery while keeping deployment changes traceable through Git.
