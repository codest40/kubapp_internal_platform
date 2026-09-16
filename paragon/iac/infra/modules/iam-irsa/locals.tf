locals {
  oidc_provider = replace(var.oidc_provider_url, "https://", "")
}
