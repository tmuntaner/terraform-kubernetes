variable "network_name" {}
variable "subnet_id" {}
variable "router_id" {}
variable "keypair" {}

variable "kubernetes_internal_address" {}
variable "image_id" {}

variable "instance_count" {
  default = 3
}
