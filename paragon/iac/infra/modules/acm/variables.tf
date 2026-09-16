variable "domain" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}


