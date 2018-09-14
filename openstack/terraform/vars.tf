variable "openstack_tenant" {}
variable "openstack_username" {}
variable "openstack_password" {}
variable "openstack_auth_url" {}
variable "regcode" {}
variable "keypair" {}
variable "subnet_id" {}

variable "subnet_cidr" {
  description = "CIDR for the VPC"
  default     = "10.240.0.0/16"
}

variable "external_network_id" {}
