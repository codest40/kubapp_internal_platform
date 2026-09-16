# Sync Route53

## What It Does

The `sync_route53.sh` script synchronizes the Kubapp DNS configuration
with AWS Route53.

It updates or verifies the Route53 records required for the Kubapp
environment so DNS points to the expected application endpoint.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed and configured.
- Valid AWS credentials with Route53 permissions.
- The target hosted zone to already exist.
- The required domain and DNS configuration to already be available.
- The application endpoint or load balancer that the DNS record should
  reference to already exist.
- The required environment variables or arguments to be provided.
