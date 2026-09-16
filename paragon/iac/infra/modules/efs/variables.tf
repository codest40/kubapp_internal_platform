variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

#variable "efs_access_points" {
#  type = map(object({
#    path = string
#    uid  = number
#    gid  = number
#  }))
#}
