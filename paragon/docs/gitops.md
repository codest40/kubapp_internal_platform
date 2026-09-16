# KubApp — GitOps Layer (ArgoCD + Helm + ApplicationSets)

## 1. Overview

The GitOps layer is the declarative delivery system of KubApp.

It sits directly on top of the Kubernetes infrastructure layer and is responsible for continuously reconciling the desired state of applications, ingress routing, and environment-specific workloads using ArgoCD.

This layer is designed as the deployment brain of the platform, where:

- Application definitions are fully declarative  
- Environment separation is strict  
- Deployment is automated via Git reconciliation  
- Infrastructure is assumed ready before workloads are introduced  

The GitOps layer is not treated as a simple deployment tool, but as a controlled lifecycle orchestrator.

---

## 2. Design Principles

This layer is intentionally structured around strict operational safety and deterministic rollout behavior.

### 2.1 Controlled Rollout Philosophy

I intentionally structure deployments in a way that only a small number of resources are introduced at a time. This reduces:

- Deployment noise in the cluster  
- Risk of cascading failures  
- Debug complexity during reconciliation  
- Network and dependency instability during rollout  

Each component is introduced in a predictable order rather than being deployed as a large uncontrolled batch.

---

### 2.2 ArgoCD First-Class Readiness Rule

I enforce a strict dependency rule:

> ArgoCD must be fully operational before any GitOps-managed application is allowed to reconcile.

This ensures:

- No orphaned deployments  
- No partial sync states  
- No premature ingress or service exposure  
- A stable control plane for all workloads  

GitOps is therefore not “installed”, but “activated only after readiness confirmation”.

---

### 2.3 Progressive Capability Expansion

The system is intentionally incomplete at early stages and evolves in layers:

- Core application deployment first  
- Ingress routing next  
- Observability and logging later  
- Policy enforcement after system stabilization  

This avoids building observability or policy systems on top of unstable workloads.

---

### 2.4 Dependency-Aware Networking Safety

Critical networking components follow strict ordering rules:

- Load Balancer Controller is introduced before ingress workloads  
- External DNS is only active after ingress exists  
- Both remain idle until Kubernetes resources require them  

This avoids early cloud resource creation, unnecessary DNS churn, and misconfigured routing.

---

## 3. System Architecture

The GitOps layer is composed of four major subsystems:

### 3.1 ArgoCD Control Plane Definitions

- root-app.yml  
- appset.yaml  
- ingress.yaml  

These define:

- The bootstrap application (root-app)  
- Dynamic application generation (ApplicationSet)  
- Ingress lifecycle management  

---

### 3.2 Helm-Based Application Runtime

A reusable Helm chart (`charts/apps`) defines all application workloads.

It standardizes:

- Deployments  
- Services  
- HPA scaling policies  
- Security context enforcement  
- Probes (readiness/liveness/startup)  

This ensures all services behave consistently regardless of environment.

---

### 3.3 Environment Layering System

Each environment is isolated under:

- `gitops/envs/dev/*`

Each service has:

- Independent `values.yaml`  
- Independent image versioning  
- Independent runtime configuration  
- Independent storage definitions  

This ensures environments do not drift or overlap.

---

### 3.4 Image Registry & Build Metadata

A structured registry layer tracks application builds:

- `gitops/registry/dev/*.json`

Each record contains:

- Image metadata  
- Runtime ports  
- Health endpoints  
- Volume configuration  
- Build fingerprints  
- Timestamped build provenance  

This allows GitOps to remain fully traceable to CI pipelines.

---

## 4. Application Deployment Flow

The deployment flow follows a strict lifecycle:

### Step 1 — Root Bootstrap

The system begins with:

- kubapp-root Application  

This initializes ArgoCD synchronization scope.

---

### Step 2 — ApplicationSet Expansion

The `appset.yaml` dynamically generates applications from:

- `gitops/envs/dev/*`

Each directory becomes a deployable unit.

This creates:

- user-dev  
- admin-dev  
- weather-dev  
- nodejsapp-dev  
- urlshortener-dev  

Each application is automatically managed by ArgoCD.

---

### Step 3 — Helm Rendering Layer

Each generated application:

- Pulls the shared Helm chart  
- Injects environment-specific values  
- Applies resource constraints  
- Enforces security context  
- Defines probes and storage  

This ensures consistency across services while allowing controlled variation.

---

### Step 4 — Ingress Consolidation

Ingress is managed separately via:

- `charts/ingress`

It performs:

- Path-based routing  
- Subdomain routing  
- TLS termination via ACM  
- ALB integration  

Ingress is intentionally decoupled so that networking only activates after workloads exist.

---

### Step 5 — Cluster Resource Activation

Once workloads stabilize:

- Load Balancer Controller becomes active  
- External DNS begins reconciliation  
- Storage drivers (EFS CSI) become operational  
- Logging (Fluent Bit) begins aggregation  

These are intentionally delayed until application traffic exists.

---

## 5. Safety Model

This GitOps layer is designed around failure containment and predictability.

### 5.1 Isolation by Design

Each application:

- Runs in its own namespace  
- Has independent scaling configuration  
- Has isolated secrets and environment data  

No cross-app dependency is assumed at runtime.

---

### 5.2 Controlled Mutation

All changes must pass through:

- Git commit  
- ArgoCD reconciliation  
- Helm rendering  

Direct cluster mutation is considered invalid in the model.

---

### 5.3 Gradual System Activation

System components are activated in sequence:

- ArgoCD  
- Applications  
- Ingress  
- Networking controllers  
- Observability  
- Policy layer (future)  

This avoids systemic coupling during early lifecycle.

---

### 5.4 Failure Containment Strategy

If a deployment fails:

- Only the affected ApplicationSet unit is impacted  
- Other services remain unaffected  
- Root application state remains stable  
- Rollback is handled via Git revert  

---

## 6. Current System State

At this stage, the GitOps layer is:

- Fully functional for multi-service deployment  
- Environment-driven via ApplicationSet  
- Integrated with Helm abstraction  
- Ingress routing operational  
- Registry-driven deployment pipeline established  

However, it is still evolving in:

- Observability integration (planned expansion)  
- Policy enforcement layer (future addition)  
- Advanced multi-environment promotion workflows  

---

## 7. Conclusion

This GitOps layer is designed as a controlled deployment engine rather than a simple configuration system.

Its primary goal is not speed, but:

- Determinism  
- Predictability  
- Safety under change  
- Clear separation of concerns  
