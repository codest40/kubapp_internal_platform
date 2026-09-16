# Register New Service

## What It Does

The `register_new_svc.sh` script registers a new application service with
Kubapp's GitOps deployment structure.

It creates or prepares the service-specific configuration required for
the platform to recognize and deploy the new service through the existing
GitOps workflow.

## What It Expects to Already Exist

The script expects:

- The Kubapp Git repository to be available.
- The required GitOps directory structure to already exist.
- The service definition and required configuration values to be provided.
- The tools required by the script to be installed.
- The target environment configuration to already exist.
- Any required service artifact or template used by the registration
  process to be available.
