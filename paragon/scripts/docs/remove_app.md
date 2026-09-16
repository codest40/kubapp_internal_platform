# Remove App

## What It Does

The `remove_app.sh` script removes an application from the Kubapp
deployment configuration.

It removes the application's GitOps configuration so the application is
no longer managed and deployed through the Kubapp platform.

## What It Expects to Already Exist

The script expects:

- A working Git repository.
- The application to already be registered in the Kubapp GitOps
  configuration.
- The application's GitOps configuration to exist in the expected
  location.
- The required command-line tools used by the script to be installed.
- GitOps configuration to be accessible and modifiable.
- Any required environment or service identifier to be provided.
