variable "cluster_name" {}
variable "subnet_id" {}
variable "network_name" {}
variable "keypair" {}
variable "image_id" {}

variable "etcd_instance_ip_addresses" {
  type = "list"
}

variable "instance_count" {
  default = 3
}
