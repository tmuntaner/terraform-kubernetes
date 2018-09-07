variable "cluster_name" {}

variable "vpc_id" {}

variable "vpc_cidr" {}
variable "gateway_id" {}

variable "subnet_ids" {
  type = "list"
}

variable "key_name" {}

variable "azs" {
  type = "list"
}

variable "depends_on" {
  default = []

  type = "list"
}
