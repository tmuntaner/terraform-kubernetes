variable "cluster_name" {}

variable "vpc_id" {}

variable "vpc_cidr" {}

variable "public_elb_id" {}

variable "internal_elb_id" {}

variable "subnet_ids" {
  type = "list"
}

variable "key_name" {}

variable "depends_on" {
  default = []

  type = "list"
}
