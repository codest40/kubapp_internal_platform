variable "profile" {
  type = string
}

variable "region" {
  type = string
}

variable "domains" {
  type = set(string)

  validation {
    condition = alltrue([
      for domain in var.domains :
      can(regex("^[A-Za-z0-9.-]+$", domain))
    ])

    error_message = "Each domain must be a valid domain name."
  }
}
