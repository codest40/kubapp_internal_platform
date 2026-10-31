# CI Design Philosophy: Runtime-Agnostic Orchestration

KUBAPP is designed to orchestrate application delivery without imposing a single application architecture, framework, or build convention.

It acts as an **orchestrator and executor, not an application definer**. Developers retain flexibility over how their applications are structured, built, tested, and configured for deployment, while KUBAPP provides the mechanisms to discover components, validate their configuration, execute CI operations, package applications, and coordinate delivery and monitoring through the platform.

This separation is intentional. KUBAPP does not need to understand an application's internal architecture or prescribe how every runtime must work. Instead, it relies on explicit configuration, runtime-specific handlers, dependency manifests, and defined execution interfaces to process applications consistently.

The goal is to support different languages, frameworks, build systems, and application requirements without coupling the platform to the assumptions of a particular application.

Runtime agnosticism does not mean that every runtime or configuration is automatically supported. Each runtime must have the necessary integration, and each component must satisfy the platform's validation and execution contracts.

**KUBAPP standardizes the delivery interface and management, not the application itself.**

## Secret Management: Cost-Conscious Design

KUBAPP uses SOPS to encrypt sensitive configuration rather than relying on AWS Secrets Manager.

This decision is driven primarily by cost. At the current stage of the platform, avoiding unnecessary recurring infrastructure costs is essential. Introducing a managed secrets service would add another cost-bearing dependency to the platform's operation and management.

SOPS allows KUBAPP to encrypt sensitive configuration while retaining control over how encrypted secrets are stored, distributed, and used. This supports the platform's security requirements without introducing the additional service costs associated with AWS Secrets Manager.

This is a deliberate trade-off based on KUBAPP's current priorities, not a claim that SOPS is universally preferable to a managed secrets service. As the platform evolves, its secret management approach can be reassessed against its security requirements, operational complexity, and cost constraints.

