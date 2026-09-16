variable "project" {
  type    = string
  default = "kubapp"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "enable_alerts" {
  type    = bool
  default = true
}

variable "account_id" {
  type = string
}
