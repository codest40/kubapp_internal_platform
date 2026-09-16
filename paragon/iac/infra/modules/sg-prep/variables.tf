variable "vpc_cidr" {
  description = "Vpc cidr blocks"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnets_cidr" {
  description = "Cidr to limit alb egress"
  type        = list(any)
}

variable "from_port_ec2_app" {
  type = number
}

variable "to_port_ec2_app" {
  type = number
}

variable "from_port_fargate_app" {
  type = number
}

variable "to_port_fargate_app" {
  type = number
}

variable "from_port_cache_app" {
  type = number
}

variable "to_port_cache_app" {
  type = number
}
variable "custom_sg_definitions" {
  description = "Optional overrides or additional security groups"
  type = map(object({
    description = string
    ingress = optional(list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = optional(list(string))
      source_sgs  = optional(list(string))
      self        = optional(bool)
      description = optional(string)
    })), [])

    egress = optional(list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = optional(list(string))
      source_sgs  = optional(list(string))
      self        = optional(bool)
      description = optional(string)
    })), [])
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
