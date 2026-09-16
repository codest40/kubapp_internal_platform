# Deployment Verification

KubApp uses runtime verification after deployment to confirm that the application and Kubernetes resources are healthy and that the deployed version is actually serving correctly.

## Purpose

The verification workflow validates the runtime state after deployment before considering the deployment successful.

It is responsible for checking:

- Kubernetes workloads
- Application availability
- Service and ingress state
- Deployed application version
- Runtime health
- Deployment readiness
- Deployment snapshot generation

## Workflow

`verify_runtime.yml`

## Verification Flow

1. Connect to the target AWS account.
2. Configure Kubernetes access.
3. Inspect deployed resources.
4. Verify workload readiness.
5. Verify services and ingress.
6. Verify application runtime.
7. Capture deployment state.
8. Publish the deployment snapshot.
9. Mark the deployment as verified.

## Relationship With Deployment

The verification stage runs after the deployment stage.

    GitOps Configuration
            |
            v
        Deployment
            |
            v
    verify_runtime.yml
            |
            +----> Kubernetes Resources
            |
            +----> Services / Ingress
            |
            +----> Application Health
            |
            +----> Deployed Version
            |
            v
    Deployment Snapshot
            |
            v
       Verified State

A deployment is therefore not considered successful simply because Kubernetes accepted the manifests. The runtime state must also be verified.

## Deployment Snapshot

The verification process produces a deployment snapshot containing information about the verified deployment.

The snapshot provides a historical reference for:

- Deployed resources
- Deployed versions
- Runtime state
- Stable deployment identification
- Rollback operations

The snapshot is later consumed by the stable-deployment and rollback workflows.

## Rollback Relationship

The verification workflow is part of the rollback chain:

    Deployment
        |
        v
    Verification
        |
        v
    Deployment Snapshot
        |
        v
    Stable Deployment
        |
        v
    Rollback

`get_stable_deploy.yml` uses the verified deployment information to identify a known stable deployment.

`rollback.yml` can then restore GitOps state to the selected stable version.

## Failure Handling

If runtime verification fails, the deployment is not treated as a healthy release.

Typical causes include:

- Pods not becoming Ready
- Failed health checks
- Incorrect service configuration
- Broken ingress routing
- Incorrect image version
- Application startup failures
- Kubernetes resource failures
- Runtime connectivity problems

Verification failures therefore provide the boundary between:

**"Kubernetes accepted the deployment"**

and

**"The application is actually healthy."**
