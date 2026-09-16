# KubApp Operational Workflows

KubApp provides a small set of operator-controlled workflows for situations
where the normal automated pipeline does not provide the required
diagnostic or intervention path.

These workflows support manual investigation, build-output inspection, and
isolated image testing.

## Workflows

| Workflow | Responsibility |
|---|---|
| `fixer.yml` | Executes controlled operator-supplied commands |
| `app_artifacts.yml` | Inspects application build artifacts |
| `docker-push.yml` | Manually builds and pushes an individual application image |

These workflows are operational tools. They do not replace the normal
build, provisioning, deployment, or verification workflows.

---

## Operational Model

The normal lifecycle remains the preferred path:

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
    Stable State

When investigation or intervention is required, the operational workflows
provide targeted entry points:

    Problem
      |
      +----> fixer.yml
      |
      +----> app_artifacts.yml
      |
      +----> docker-push.yml
      |
      v
    Diagnose / Test / Correct
      |
      v
    Verify

---

# Manual Fixer

## `fixer.yml`

`fixer.yml` provides an operator-controlled mechanism for executing commands
against the selected KubApp environment.

The operator supplies:

- an environment;
- one or more commands.

Commands are executed sequentially through Bash.

Examples include:

    terraform state list

    kubectl get ns

The workflow is intended for controlled operational work that does not
already have a dedicated automation path.

---

## Fixer Flow

    Manual Trigger
         |
         v
    Select Environment
         |
         v
    Provide Commands
         |
         v
    Checkout Repository
         |
         v
    Configure AWS Access
         |
         v
    Prepare Terraform / Kubernetes Access
         |
         v
    Execute Commands
         |
         v
    Inspect Result

The workflow provides access to infrastructure and Kubernetes tooling
required for investigation and controlled intervention.

---

## Typical Uses

`fixer.yml` can be useful for:

- inspecting Terraform state;
- inspecting Kubernetes resources;
- checking namespaces;
- investigating ingress configuration;
- checking infrastructure state;
- testing an operational command before automating it;
- performing controlled recovery actions.

It is particularly useful when an operational problem does not yet justify
creating a dedicated workflow or script.

---

## Safety

`fixer.yml` executes commands supplied by the operator and therefore has
greater operational power than a predefined diagnostic workflow.

Operators should:

- review commands before execution;
- select the intended environment carefully;
- test potentially destructive actions in development first;
- avoid unnecessary production modifications;
- prefer existing automation when an appropriate workflow already exists.

The workflow should therefore be treated as an **operational escape hatch**,
not as the normal deployment mechanism.

---

# Build Artifact Inspection

## `app_artifacts.yml`

`app_artifacts.yml` provides a manual way to inspect artifacts produced by
the application build process.

It is useful when the problem may exist between application build output
and GitOps registry generation.

Typical questions include:

    Was the expected image metadata generated?

    Was the correct service recorded?

    Was the correct environment recorded?

    Was the registry artifact created?

The workflow allows operators to inspect the generated output without
modifying the deployment configuration.

The artifact lifecycle itself is documented in **CI/CD Artifacts**.

---

# Manual Docker Image Testing

## `docker-push.yml`

`docker-push.yml` provides an isolated manual path for building and pushing
a specific application image.

The operator identifies the application Docker directory, for example:

    docker/<service>

The workflow then:

1. Verifies that the requested directory exists.
2. Configures Docker Buildx.
3. Authenticates with Docker Hub.
4. Builds the image.
5. Pushes the image.
6. Publishes the supported image tags.

Typical tags include:

    <registry>/<service>:latest

    <registry>/<service>:<commit-sha>

This workflow is useful when an operator needs to test an application image
without executing the complete KubApp build lifecycle.

It should not be confused with `build.yml`, which is responsible for the
normal application build and registry-generation path.

---

# Operational vs Automated Workflows

KubApp separates normal lifecycle automation from operator tools.

| Workflow | Purpose | Normal Lifecycle |
|---|---|---|
| `build.yml` | Builds application images | Yes |
| `add_new_app.yml` | Generates application GitOps configuration | Yes |
| `setup_argocd.yml` | Handles deployment synchronization | Yes |
| `verify_runtime.yml` | Verifies deployed applications | Yes |
| `fixer.yml` | Manual operational intervention | No |
| `app_artifacts.yml` | Build-output inspection | No |
| `docker-push.yml` | Isolated image testing | No |

The operational workflows exist to support the automated platform rather
than become an alternative deployment system.

---

# Operational Principle

KubApp follows a simple operational principle:

    Automate the normal path
             |
             v
        Detect Problem
             |
             v
           Diagnose
             |
             v
    Controlled Intervention
             |
             v
          Verify
             |
             v
    Repeated Fix Identified
             |
             v
    Convert Into Automation

Manual intervention is therefore treated as a controlled exception to the
normal lifecycle.

If the same manual operation is repeatedly required, it should eventually
be moved into the appropriate workflow, script, or infrastructure
configuration so that the platform becomes more predictable and less
dependent on manual intervention.
