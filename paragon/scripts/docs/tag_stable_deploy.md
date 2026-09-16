# Tag Stable Deploy

## What It Does

The `tag_stable_deploy.sh` script marks a deployment as a stable version
in Git.

It creates or updates the Git tag used to identify the stable deployment
version so the release can be referenced consistently by the deployment
and GitOps workflow.

## What It Expects to Already Exist

The script expects:

- Git to be installed.
- The current directory to be inside the Kubapp Git repository.
- The target commit or deployment to already exist.
- Git access and permission to create or update the required tag.
- Any required environment variables or arguments used by the script to
  identify the stable deployment to be available.
