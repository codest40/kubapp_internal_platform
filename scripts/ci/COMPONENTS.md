# Components of KUBAPP CI

## 1. Application Discovery and Validation

- `detect_runtime.py` discovers application components under `docker/`, reads their CI configurations, and identifies supported runtimes.
- `validate.py` checks application configuration, required files, runtime consistency, custom scripts, commands, environment settings, and health-check definitions.
- `variables.py` provides shared runtime images, manifest definitions, and related configuration.

## 2. CI Orchestration and Runtime Handling

- `dependency_abstractor.py` coordinates the overall CI process, processes components concurrently, collects successful build results, and writes `final_ci_data.json`.
- `python_handler.py` and `node_handler.py` implement runtime-specific dependency preparation and application checks.
- `run_ci.py` selects the configured custom-script or standard-check execution path.
- `dependency_mgt.py`, `python_mgt.py`, and `node_mgt.py` manage dependency preparation, vulnerability auditing, and software bills of materials (SBOMs) for supported runtimes.
- Python dependency auditing uses `pip-audit`, while Node.js dependency auditing uses `npm audit`.

## 3. Command Execution and Environment Isolation

- `manage_env.py` prepares component environment variables and decrypts configured secrets using SOPS.
- `component_execution_env.py` defines the component command-execution boundary and its execution policies.
- `podman_execution.py` runs component-controlled commands inside disposable Podman containers with configured resource limits and filesystem restrictions.
- `command_policy.py` applies command and argument restrictions using policies defined in `command_policy.json`.
- `reuse.py` provides shared helpers and separates trusted platform operations from component-controlled command execution.
- `check_podman_capability.py` assesses available Podman isolation capabilities. Its current role is diagnostic rather than an enforcement gate.
- `check_python.sh` checks for Python and Podman and attempts to install missing system packages.

## 4. AI-Assisted Assessment

- `ai_analysis.py` selects the applicable ruleset for an artifact and coordinates its assessment.
- `ai/client.py` communicates with the assessment service over MCP.
- `ai/server.py` validates assessment requests, communicates with the configured AI provider, and validates model responses.
- `ai/setup_provider.py` configures and checks the supported AI providers.
- `ai/__init__.py` and `ai/providers/__init__.py` provide Python package initialization for the AI modules and provider package.
- `platform_decision.py` validates assessment decisions and records reports.
- `ai/rules/rules.json` and the specialized rule files define assessment criteria for applicable artifacts.

### AI Assessment Rules

- `ai/rules/commands.json` defines assessment rules for commands.
- `ai/rules/dockerfile.json` defines assessment rules for Dockerfiles.
- `ai/rules/modules.json` defines assessment rules for modules and dependencies.
- `ai/rules/scripts.json` defines assessment rules for scripts.
- `ai/rules/security.json` defines additional security assessment rules.
- `ai/rules/rules.json` provides the general assessment rules configuration.

## 5. Image Building, Validation, and Publication

- `app_validator.py` handles image tagging, inspection, registry authentication, and image publication.
- `container.py` starts built application containers, tests configured HTTP health-check endpoints, and collects logs when checks fail.
- `dependency_abstractor.py` coordinates these operations and records successful application results for downstream workflows.

## 6. Overall Execution Flow

Discover applications → Validate configuration → Prepare execution environments and dependencies → Assess applicable artifacts → Execute checks → Build images → Test container health → Publish successful images → Write CI results for GitOps.

## Documentation Scope

This document provides a high-level overview of KUBAPP CI components and their responsibilities. Detailed implementation, design reasoning, security considerations, and operational behavior are documented in the corresponding files under `docs/`.
