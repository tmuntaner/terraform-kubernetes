variable "cluster_name" {}
variable "network_name" {}
variable "subnet_id" {}
variable "router_id" {}
variable "keypair" {}

variable "instance_count" {
  default = 3
}

variable "kubernetes_internal_address" {}
