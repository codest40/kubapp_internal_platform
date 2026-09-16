variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from EKS"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL from EKS"
  type        = string
}

variable "account_id" {
  description = "acc  id"
  type        = string
}

variable "hosted_zone_id" {
  type = string
}

variable "region" {
  description = "acc  id"
  type        = string
}

variable "tags" {
  description = "Tags for IAM resources"
  type        = map(string)
  default     = {}
}
