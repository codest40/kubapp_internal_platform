# KubApp Deployment

KubApp uses GitOps-driven deployment to move validated application configuration from the repository into the Kubernetes cluster through Argo CD.

The deployment stage begins after application build and GitOps provisioning have completed.

## Deployment Flow

    Application Source
          |
          v
       build.yml
          |
          v
    Registry Metadata
          |
          v
    add_new_app.yml
          |
          v
      GitOps Config
          |
          v
    setup_argocd.yml
          |
          v
        Argo CD
          |
          v
      Kubernetes
          |
          v
    verify_runtime.yml
          |
          v
    Runtime Verified

## Deployment Workflows

| Workflow | Responsibility |
|---|---|
| `setup_argocd.yml` | Configures and synchronizes Argo CD applications |
| `verify_runtime.yml` | Verifies the deployed runtime state |
| `activate_pipeline.yml` | Orchestrates build, provisioning, deployment, and verification |

## Deployment Model

KubApp does not deploy application workloads directly from the CI runner.

The CI/CD pipeline generates the desired Kubernetes configuration and commits it to Git.

Argo CD then uses the Git repository as the desired state and reconciles Kubernetes against that state.

    Git Repository
          |
          | Desired State
          v
        Argo CD
          |
          | Reconciliation
          v
     Kubernetes Cluster
          |
          v
     Application Workloads

This separates:

- **CI** — building and preparing application artifacts.
- **GitOps** — storing the desired deployment configuration.
- **CD** — synchronizing the desired configuration into Kubernetes.
- **Runtime verification** — confirming that the resulting deployment is healthy.

## Deployment Prerequisites

Before deployment begins, the following should already exist:

1. Docker image successfully built and pushed.
2. Registry metadata generated.
3. GitOps configuration generated.
4. Ingress configuration registered.
5. GitOps validation completed.
6. Changes committed to Git.
7. Kubernetes cluster available.
8. Argo CD available.

The deployment stage therefore consumes the output of the previous pipeline stages rather than rebuilding application configuration.

## Argo CD

Argo CD is the deployment controller used by KubApp.

Its responsibility is to continuously reconcile the Kubernetes cluster with the GitOps configuration stored in the repository.

Conceptually:

    Git
     |
     | Desired configuration
     v
    Argo CD
     |
     | Sync
     v
    Kubernetes

If the cluster differs from the configuration stored in Git, Argo CD can reconcile the difference according to the configured synchronization policy.

## Application Deployment

An application follows this lifecycle:

    Docker Image
         |
         v
    Registry Metadata
         |
         v
    GitOps Values
         |
         v
    Argo CD Application
         |
         v
    Kubernetes Deployment
         |
         v
    Pods
         |
         v
    Service
         |
         v
    Ingress

The image reference generated during the build stage becomes part of the application deployment configuration.

This allows Kubernetes to deploy the exact image associated with the GitOps change.

## Argo CD Setup

`setup_argocd.yml` is responsible for preparing the Argo CD deployment path.

The workflow operates against the target EKS cluster and configures the required Argo CD resources.

The exact deployment configuration is maintained in the repository's GitOps and Kubernetes configuration rather than being manually created from the CI runner.

## Deployment Synchronization

Once GitOps configuration has been committed, Argo CD detects the repository state.

The desired state can then be synchronized into Kubernetes.

    Git Commit
         |
         v
    Argo CD detects change
         |
         v
    Application becomes OutOfSync
         |
         v
    Argo CD Sync
         |
         v
    Kubernetes resources updated
         |
         v
    Application becomes Synced

The important distinction is that a successful Git commit does not by itself prove that the application is successfully running.

That is why KubApp has a separate runtime verification stage.

## Runtime Verification

`verify_runtime.yml` validates the deployed environment after synchronization.

The verification stage is responsible for confirming that the deployment produced the expected runtime state.

Typical verification areas include:

- Kubernetes workloads
- Pods
- Services
- Ingress
- Argo CD application state
- Application availability
- Deployment health

The verification workflow therefore acts as the final gate between deployment and a stable deployment state.

## Deployment vs Runtime Verification

These are intentionally separate stages.

| Stage | Question |
|---|---|
| GitOps provisioning | Is the desired configuration correctly generated? |
| Argo CD deployment | Was the desired state synchronized? |
| Runtime verification | Is the application actually healthy? |

An Argo CD application can be synchronized while the application itself is still unhealthy.

For example:

    GitOps: Valid
    Argo CD: Synced
    Kubernetes: Running
    Application: Unhealthy

Runtime verification exists to detect this type of failure.

## Deployment Verification Flow

    GitOps Configuration
            |
            v
        Argo CD Sync
            |
            v
    Kubernetes Resources
            |
            v
       Pod Readiness
            |
            v
     Service Availability
            |
            v
      Ingress Availability
            |
            v
      Runtime Verification
            |
        +---+---+
        |       |
       PASS    FAIL
        |       |
        v       v
      Stable  Pipeline
      Deploy  Failure

## Deployment Snapshot

The runtime verification process also produces deployment information used by later lifecycle operations.

The stable deployment information can be associated with:

- Git commit
- Deployment run
- Environment
- Deployed configuration
- Deployment state

This information becomes important during rollback.

See `Rollback`.

## Stable Deployment

KubApp treats a deployment as stable only after the deployment and runtime verification stages have succeeded.

The conceptual lifecycle is:

    Build
      |
      v
    Provision
      |
      v
    Deploy
      |
      v
    Verify
      |
      v
    Stable

This distinction is important because the latest Git commit is not necessarily the latest known-good deployment.

## Failure Handling

If deployment fails, the pipeline should not treat the deployment as stable.

Possible failure points include:

| Stage | Example Failure |
|---|---|
| GitOps | Invalid generated configuration |
| Argo CD | Application cannot synchronize |
| Kubernetes | Deployment cannot become ready |
| Pods | CrashLoopBackOff |
| Service | No available endpoints |
| Ingress | Route unavailable |
| Runtime verification | Health check failure |

The failed deployment can then be investigated or rolled back to a previously verified stable state.

## Relationship With Rollback

Rollback operates on the distinction between:

- The current Git state
- The previously verified stable state

The stable deployment information allows KubApp to identify a known-good deployment rather than simply reverting to an arbitrary previous commit.

See `get_stable_deploy.yml` for the rollback selection process.

## Relationship With Cleanup

Deployment is not responsible for deleting obsolete workloads.

Cleanup and orphan reconciliation are handled separately through:

- `clean_argocd.yml`
- `remove_app.yml`
- `remove_svc.yml`

This separation prevents deployment logic from becoming responsible for unrelated lifecycle operations.

## Pipeline Orchestration

`activate_pipeline.yml` provides manual orchestration over the major pipeline stages.

Available modes include:

| Mode | Purpose |
|---|---|
| `full` | Build, provisioning, deployment, and cleanup sequence |
| `build` | Build-related workflows |
| `deploy` | Deployment-related workflows |
| `cleanup` | Cleanup workflow |

The workflow therefore provides an operational entry point for executing selected portions of the lifecycle.

## Deployment Responsibilities

| Component | Responsibility |
|---|---|
| `build.yml` | Builds and publishes container images |
| `add_new_app.yml` | Generates GitOps deployment configuration |
| `setup_argocd.yml` | Configures and synchronizes Argo CD |
| Argo CD | Reconciles Git state with Kubernetes |
| Kubernetes | Runs the application workloads |
| `verify_runtime.yml` | Verifies the deployed runtime |
| `get_stable_deploy.yml` | Identifies the known stable deployment |
| `rollback.yml` | Restores a previous deployment state |
