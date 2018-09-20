variable "cluster_name" {}
variable "network_name" {}
variable "keypair" {}

variable "instance_count" {
  default = 3
}

variable "kubernetes_internal_address" {}
