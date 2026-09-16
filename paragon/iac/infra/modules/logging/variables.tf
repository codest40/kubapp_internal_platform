variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "log_groups" {
  description = "Map of log groups to create"
  type = map(object({
    name      = string
    retention = number
    log_type  = string
    scope     = string
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}

