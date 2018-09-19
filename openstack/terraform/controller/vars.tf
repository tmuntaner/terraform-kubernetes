variable "cluster_name" {}
variable "network_name" {}
variable "keypair" {}

variable "etcd_instance_ip_addresses" {
  type = "list"
}

variable "instance_count" {
  default = 3
}
