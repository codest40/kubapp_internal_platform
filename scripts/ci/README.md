# KUBAPP CI

KUBAPP CI is the platform's application build, security validation, and image delivery component. It manages the workflow that prepares application images for downstream KUBAPP deployment stages, with security and controlled execution treated as core requirements.

## Purpose and Scope

KUBAPP CI centralizes application discovery, configuration validation, dependency preparation, security checks, application testing, image building, and publication. It is designed as a distinct, independently manageable component that integrates with the wider KUBAPP platform through defined responsibilities and outputs.

This separation allows CI to evolve independently while continuing to contribute reliably to KUBAPP's application delivery workflow. Security is a foundational consideration: application inputs are validated, executable operations are controlled, and required checks must pass before an application can progress through the normal delivery process.

## Design Approach

KUBAPP CI follows a practical, security-conscious design approach built around four priorities: **secure execution environments, cost-effective resource usage, simplicity that works reliably, and runtime agnosticism**.

The goal is to solve real platform requirements without introducing unnecessary complexity. Design decisions are guided by their practical value, favoring solutions that are understandable, maintainable, and effective over abstractions that add little operational benefit.

The architecture separates shared CI responsibilities from runtime-specific application handling. Python and Node.js are currently supported, while the design aims to accommodate additional runtimes through compatible handlers and dependency-management implementations without requiring a complete redesign.

KUBAPP also aims to balance platform control with developer freedom. Developers can define application-specific validation and testing requirements, while KUBAPP retains responsibility for the shared workflow, security boundaries, and conditions for successful delivery.

## Key Engineering Decisions and Trade-offs

### 1. Controlled Command Execution and Isolation

KUBAPP treats developer-supplied commands, scripts, and other executable inputs as potentially malicious by default. The objective is to prevent application-level execution from unnecessarily exposing the platform or its underlying host to risk.
Component-controlled commands run through a dedicated Podman execution boundary. Restrictions are intended to limit filesystem access, privileges, network connectivity, and resource consumption, while command policies provide additional control over permitted commands and arguments.
This prioritizes platform protection over unrestricted execution flexibility. The trade-off is additional execution overhead and the need to manage compatibility, environment constraints, and the limitations of container-based isolation.
Currently uses `pip-audit` to check Python application dependencies for known vulnerabilities and `npm audit` for Node.js application dependencies. These checks are managed by KUBAPP as part of its centralized dependency security process.

### 2. AI-Assisted Security Assessment

Static command policies alone cannot evaluate every potential security risk in developer-supplied inputs. KUBAPP therefore uses AI-assisted assessment to analyze applicable artifacts and provide findings that can inform platform decisions.

Through its Model Context Protocol (MCP) integration, KUBAPP CI supports Ollama for local model execution, OpenAI API models, and Google's Gemini API. This provides flexibility to select a provider based on available computing resources, assessment requirements, and operational preferences.

**AI advises; KUBAPP decides.** The AI layer does not execute assessed artifacts or independently authorize CI operations. KUBAPP retains operational authority through its own validation rules and decision logic.

AI assessment introduces additional processing time and dependence on the configured provider. To manage contention during concurrent builds, KUBAPP serializes assessment requests through a controlled locking mechanism and allows additional time for assessments to complete. This improves control over assessment execution but can increase overall pipeline duration.

### 3. Centralized Dependency Security and SBOM Generation

KUBAPP CI takes responsibility for dependency installation, vulnerability checks, and SBOM generation rather than delegating these core operations to developer-supplied scripts.

Dependency installation requires network access and sufficient filesystem permissions to retrieve packages and prepare dependency artifacts. KUBAPP therefore uses a separately prepared container environment for this work, while developer-controlled commands run through the more restrictive Podman execution boundary.

Dependency vulnerability checks are part of the required build workflow. Failures in required checks prevent the affected component from progressing normally. SBOM generation also provides a record of application dependencies, improving visibility into the components included in a build.

Centralizing these responsibilities gives KUBAPP greater control over dependency security and consistency. The trade-off is additional processing time, environment-management complexity, and the need to implement compatible dependency-management workflows as new runtimes are introduced.

### 4. Concurrent Builds and Component Separation

KUBAPP processes application components concurrently to reduce overall build time. Each component build runs in its own thread and is designed to use a dedicated, non-shared execution environment, keeping its working state, environment variables, and execution context separate from other components and the local host.

This approach improves throughput while aiming to prevent cross-component interference and unintended data corruption. The trade-off is additional resource consumption and the need to manage shared platform state and host-level operations carefully.

AI assessment remains a serialized operation within this concurrent workflow, so components may wait for assessment access even when their builds are otherwise running concurrently.

### 5. Container Health Verification Before Publication

A successful image build does not necessarily mean the application inside the image will run correctly. KUBAPP CI therefore starts the built application container and tests its configured health endpoints before publishing the image.

This acts as the final application validation stage. If the container fails to start or the required health checks fail, the component's build is marked unsuccessful and its image is not published through the normal CI workflow.

The trade-off is additional execution time and resource consumption in exchange for greater confidence that published images contain applications that start and respond as expected.

### 6. Developer Flexibility and Configuration Requirements

KUBAPP is intended to be an open-ended platform that accommodates different applications and development preferences. Developers can supply application-specific CI commands and scripts to define requirements such as linting, application-specific security analysis, and unit testing.

Each application must provide the required configuration values in a `ci.yml` file within its application root directory under `docker/`. KUBAPP discovers this configuration automatically and uses it to determine the component's CI requirements and execution path.

This establishes a consistent configuration contract while allowing flexibility in application-specific checks. The trade-off is that developer-supplied execution introduces security and compatibility considerations, requiring configuration validation, command policies, AI-assisted assessment where applicable, and controlled execution.

**The goal is to give developers meaningful freedom without making platform security optional.**

### 7. Failure Handling and Security Gates

KUBAPP CI uses security and validation gates throughout the workflow so that individual stages can enforce their requirements before allowing processing to continue.

The `STRICT_MODE` and `FAIL_MODE` settings control different aspects of failure handling. `STRICT_MODE` determines whether validation failures prevent builds from proceeding, while `FAIL_MODE` determines how component build failures affect the overall CI result.

This allows users to choose how the workflow responds when one component fails while others may still succeed. The trade-off is additional configuration complexity and the need to maintain clear failure semantics without allowing required security checks to be bypassed.

### 8. Runtime Extensibility and Responsibility Separation

Each runtime handler manages the application-specific execution and checks required by its runtime. Shared CI responsibilities remain centralized, including dependency security management, image building, image inspection, container health verification, and delivery-result generation.

This separation is intended to make future runtime support easier to implement without duplicating shared platform functionality or redesigning the entire workflow.

The trade-off is that each additional runtime still requires a compatible handler and dependency-management implementation that integrates correctly with KUBAPP's existing execution and security boundaries.

### 9. Cost-Conscious Engineering and Open-Source Tools

Cost-effectiveness is a core design consideration throughout KUBAPP. The platform favors available free resources and open-source technologies wherever they can meet its functional, security, and operational requirements.

For example, KUBAPP uses SOPS with age encryption for secret management instead of relying on a paid secrets-management service. This provides a cost-effective approach while keeping secret-management responsibilities within the platform.

KUBAPP has been developed and tested under modest computing constraints, including a laptop with 16 GB of RAM, a four-core CPU, and no dedicated GPU or NVIDIA hardware. Its CI workflow also operates on GitHub Actions' free Linux runner resources without requiring specialized hardware.

These constraints influence implementation choices, but they do not prevent KUBAPP from benefiting from more capable environments. Additional computing resources may improve certain operations, particularly local AI assessment. For example, running a larger Ollama model than `qwen2.5:3b` may improve assessment capabilities, depending on the model and available resources.

The trade-off is that constrained infrastructure can limit computing capacity and shift more responsibility for configuration, maintenance, security, and troubleshooting onto KUBAPP. The goal is not simply to choose the cheapest option, but to build a practical platform that remains useful within modest resource limits and can benefit from additional capacity when available.

### 10. CI Results and Downstream Integration

KUBAPP CI writes successful build information to `gitops/state/final_ci_data.json`. Downstream workflows and platform sections consume this information, including application names, application directories, and image references required for subsequent delivery and deployment operations.

This defined output allows CI to focus on application validation, security checks, image building, and publication without taking ownership of downstream deployment responsibilities.

The trade-off is that downstream stages depend on the result file's structure and accuracy, so its contents must remain consistent with their requirements.

## CI Workflow

```text
Application Source
        |
        v
      docker/
        |
        v
 Application Discovery
        |
        v
 Configuration Validation
        |
        v
 Runtime-Specific Handling
        |
        v
 Dependency Preparation
 and Security Checks
        |
        v
 AI-Assisted Assessment
 and Controlled Execution
        |
        v
 Application Checks
 and Container Image Build
        |
        v
 Image and Container
 Health Verification
        |
        v
 Image Publication
        |
        v
gitops/state/final_ci_data.json
        |
        v
 Downstream KUBAPP
 Delivery / GitOps Stages
```

The exact execution path depends on the application's runtime and configuration. Required validation, security, and health checks must be satisfied for a component to progress through the normal publication workflow, subject to the configured failure-handling behavior.

## Documentation

See [`COMPONENTS.md`](COMPONENTS.md) for an overview of CI components and their responsibilities. Additional documentation under [`docs/`](docs/) covers individual scripts, configuration inputs, execution behavior, dependencies, and failure handling.

## Continuous Improvement

KUBAPP CI is intended to evolve through practical improvements to its security controls, architecture, resource efficiency, developer experience, and execution workflow. Suggestions for better approaches are welcome, provided they strengthen the platform without introducing unnecessary complexity or compromising its core design priorities.
