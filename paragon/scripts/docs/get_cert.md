# Get Certificate

## What It Does

The `get_cert.sh` script retrieves or inspects the TLS certificate required
by the Kubapp environment.

It is used to obtain certificate information needed by the platform's
HTTPS configuration and certificate-related AWS resources.

## What It Expects to Already Exist

The script expects:

- AWS CLI to be installed and configured.
- The required AWS credentials and permissions.
- The target AWS region to be configured.
- The certificate or certificate-related AWS resource to already exist.
- Any domain, certificate ARN, or other required input expected by the
  script to be available.
