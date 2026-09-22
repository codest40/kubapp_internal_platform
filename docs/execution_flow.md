# KubApp — Execution Flow

KubApp is a Kubernetes-based platform that provisions infrastructure, manages application deployments through GitOps, and continuously verifies the state of the running platform.

## 1. Infrastructure Provisioning

Terraform provisions the AWS foundation required by KubApp.

This includes:

* VPC and networking
* EKS cluster
* IAM roles and OIDC
* Required AWS integrations
* Terraform remote state

The result is a ready Kubernetes environment.

---

## 2. Kubernetes Platform Bootstrap

The Kubernetes cluster is configured with the platform components required to run KubApp.

This includes:

* ArgoCD
* ingress and load balancing
* external DNS
* storage integrations
* observability components
* required Kubernetes configuration

---

## 3. GitOps Deployment

Application configuration is maintained in Git.

ArgoCD watches the GitOps configuration and reconciles the Kubernetes cluster with the desired state.

```text
Git
 ↓
ArgoCD
 ↓
Kubernetes
 ↓
Application
```

Changes to the GitOps configuration therefore become changes to the running workloads.

---

## 4. Runtime Verification

After deployment, KubApp verifies that the resulting system is operating correctly.

Verification includes:

* Kubernetes workload health
* ArgoCD synchronization and health
* service availability
* ingress routing
* application readiness

The goal is to confirm that the desired state has actually become a healthy running system.

---

## 5. Observability

KubApp continuously collects operational information from the platform.

The observability layer provides visibility into:

* Kubernetes resources
* application metrics
* logs
* workload health
* infrastructure behavior
* deployment state

This provides the feedback needed to understand the platform while it is running.

---

## Execution Model

The current platform can therefore be summarized as:

```text
   Git Push
     ↓
Continous Integration
     ↓
Infrastructure
     ↓
Kubernetes
     ↓
GitOps
     ↓
Deployment
     ↓
Verification
     ↓
Observability
```

KubApp's goal is to keep the running Kubernetes environment aligned with the desired configuration stored in Git while providing the operational visibility needed to detect and investigate problems.

