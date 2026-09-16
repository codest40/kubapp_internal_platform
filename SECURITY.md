# Security Checklist

### Security Framework Alignment

The security controls in KUBAPP can be mapped to common security
principles such as least privilege, identity-based access, encryption,
auditability, secure software supply chain practices, and separation
of duties.

This document describes the controls implemented by the project; it
does not constitute a formal compliance certification.

### Before deployment

- [ ] No secrets committed to Git
- [ ] GitHub App configured with required permissions only
- [ ] GitHub Actions permissions reviewed
- [ ] AWS IAM role uses restricted trust policy
- [ ] Terraform state backend is protected
- [ ] Container image are scanned
- [ ] Dependencies are checked
- [ ] Kubernetes manifests validated
- [ ] Production changes reviewed

### Runtime

- [ ] Workloads run with appropriate security contexts
- [ ] Network access is restricted
- [ ] Kubernetes RBAC is restricted
- [ ] Application secrets are not embedded in images
- [ ] Logs and security events are available
- [ ] Runtime health checks are active
