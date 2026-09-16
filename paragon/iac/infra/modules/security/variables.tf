
variable "vpc_id" {
  description = "VPC ID where SGs will be created"
  type        = string
}

variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "sg_definitions" {
  description = "Map of SG definitions keyed by name"
  type = map(object({
    description    = string
    self_reference = optional(bool, false)

    ingress = optional(list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = optional(list(string), [])
      source_sgs  = optional(list(string), [])
      description = optional(string)
    })), [])

    egress = optional(list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = optional(list(string), [])
      source_sgs  = optional(list(string), [])
      description = optional(string)
    })), [])
  }))
}

variable "tags" {
  description = "Extra tags to add to all SGs"
  type        = map(string)
  default     = {}
}
