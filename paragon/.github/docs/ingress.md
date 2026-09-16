# KubApp Ingress Management

KubApp uses a shared ingress model where application and internal platform services are registered into an environment-specific ingress configuration.

Instead of creating an independent ingress definition for every application, KubApp maintains a centralized service registry for routing.

---

## Ingress Architecture

    Application Registry
           │
           ▼
    add_new_app.yml
           │
           ▼
    register_new_svc.sh
           │
           ▼
    gitops/ingress/<env>/values.yaml
           │
           ▼
    Shared Ingress Helm Configuration
           │
           ▼
    Kubernetes Ingress
           │
           ▼
    Service
           │
           ▼
    Application / Platform Backend

---

## Ingress Structure

Ingress configuration is separated by environment:

    gitops/
    └── ingress/
        ├── dev/
        │   └── values.yaml
        └── prod/
            └── values.yaml

Each environment therefore maintains its own routing configuration.

This prevents a service registered in one environment from automatically becoming available through another environment's ingress.

---

## Shared Ingress Model

KubApp uses a shared ingress rather than creating a separate ingress resource for every application.

The model is conceptually:

                         Shared Ingress
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
           app-one         app-two        app-three
              │               │               │
              ▼               ▼               ▼
           Service          Service          Service
              │               │               │
              ▼               ▼               ▼
            Pods             Pods             Pods

This provides a single routing layer while allowing multiple applications and platform services to participate in the same ingress configuration.

---

## Service Registration

Applications are registered automatically by `add_new_app.yml`.

The workflow calls:

    scripts/register_new_svc.sh "$SERVICE" "$ENV"

The script updates the appropriate environment's ingress configuration.

For example:

    gitops/ingress/dev/values.yaml

The application therefore becomes part of the environment's shared routing configuration without requiring manual ingress editing.

---

## Application Registration

Application registry entries use:

    type: App

When the provisioning workflow encounters an application, it:

1. Reads the service metadata.
2. Generates the application's deployment configuration.
3. Determines the application service information.
4. Registers the service with ingress.
5. Validates the resulting GitOps configuration.

The registration is performed after the application's registry metadata has been validated.

---

## Backend Registration

KubApp also registers internal platform services.

These use:

    type: Backend

Examples include:

| Service | Backend Service | Port |
|---|---|---:|
| Grafana | `kube-prometheus-stack-grafana` | 3000 |
| Prometheus | `kube-prometheus-stack-prometheus` | 9090 |
| Alertmanager | `kube-prometheus-stack-alertmanager` | 9093 |
| Argo CD | `argocd-server` | 8080 |

These services already exist inside the cluster, so ingress registration points to their existing Kubernetes services rather than creating application workloads.

---

## Application vs Backend

The ingress system supports two different service sources.

| Type | Workload Created? | Backend |
|---|---|---|
| `App` | Yes | Application Kubernetes Service |
| `Backend` | No | Existing platform Kubernetes Service |

This allows the same ingress layer to expose both user applications and internal platform components.

---

## Environment Isolation

Ingress configuration is environment-specific.

For example:

    gitops/ingress/dev/values.yaml

and:

    gitops/ingress/prod/values.yaml

are independent configurations.

The provisioning workflow also verifies that the environment recorded in application metadata matches the environment being processed.

This prevents accidental registration of a development application into the production ingress configuration.

---

## Removing a Service

Services can be removed through:

    remove_svc.yml

The workflow accepts one or more service names.

Examples:

    chatbot

or:

    chatbot,nodejsapp

The workflow normalizes the input and calls:

    scripts/register_new_svc.sh remove "$svc" "$ENV"

The service is then removed from:

    gitops/ingress/<env>/values.yaml

---

## Service Removal Flow

    Manual Request
           │
           ▼
    remove_svc.yml
           │
           ▼
    register_new_svc.sh remove
           │
           ▼
    gitops/ingress/<env>/values.yaml
           │
           ▼
    GitOps Validation
           │
           ▼
    Git Commit
           │
           ▼
    remove_app.yml
           │
           ▼
    Orphan Reconciliation

Removing a service from ingress does not immediately mean that the application directory is deleted.

Instead, KubApp uses a separate reconciliation workflow to determine whether the application has become orphaned.

---

## Orphan Reconciliation

`remove_app.yml` compares the applications represented in:

    gitops/envs/<env>/

against the services registered in:

    gitops/ingress/<env>/values.yaml

An application directory that is no longer represented in ingress is considered an orphan.

The reconciliation process can then remove the orphaned application configuration.

Conceptually:

    gitops/envs/dev/
           │
           │ compare
           ▼
    gitops/ingress/dev/values.yaml
           │
           ▼
    Is application registered?
           │
       ┌───┴───┐
       │       │
      YES      NO
       │       │
      KEEP    ORPHAN
                │
                ▼
            Remove app

Production deletion is blocked by the reconciliation workflow.

---

## Validation

Ingress configuration is validated before changes are committed.

The workflows use `yq` to verify that the environment-specific values file contains valid YAML.

The complete GitOps structure is then validated with:

    scripts/validate_gitops.sh

This creates two levels of validation:

1. YAML syntax validation.
2. KubApp GitOps structure validation.

---

## Ingress Lifecycle

The complete lifecycle of an application route is:

    Application Created
           │
           ▼
    Build Pipeline
           │
           ▼
    Registry Entry
           │
           ▼
    GitOps Provisioning
           │
           ▼
    Ingress Registration
           │
           ▼
    Git Commit
           │
           ▼
    Argo CD
           │
           ▼
    Kubernetes Ingress
           │
           ▼
    Application Available

Removal follows the reverse logical path:

    Remove Service
           │
           ▼
    Ingress Registration Removed
           │
           ▼
    Git Commit
           │
           ▼
    Orphan Reconciliation
           │
           ▼
    Application Configuration Removed

---

## Safety Model

KubApp separates **routing removal** from **application deletion**.

This is intentional.

Removing a route first prevents traffic from continuing to reach an application before the application's configuration is considered for deletion.

The reconciliation workflow then determines whether the application is genuinely orphaned.

Production deletion is explicitly protected.

---

## Ingress Responsibilities

| Component | Responsibility |
|---|---|
| `add_new_app.yml` | Registers new applications and backend services |
| `register_new_svc.sh` | Adds or removes service registrations |
| `gitops/ingress/<env>/values.yaml` | Source of truth for environment routing |
| `remove_svc.yml` | Explicitly removes services from ingress |
| `remove_app.yml` | Reconciles orphaned application directories |
| `validate_gitops.sh` | Validates GitOps configuration |
| Argo CD | Synchronizes the resulting configuration to Kubernetes |
