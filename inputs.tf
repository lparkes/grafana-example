variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "dns_zone_id" {
  type = string
}

variable "dns_domain" {
  type = string
}
