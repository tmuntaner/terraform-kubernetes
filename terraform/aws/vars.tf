variable "vpc_cidr" {
  description = "CIDR for the VPC"
  default     = "10.240.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the public subnet"
  default     = "10.240.0.0/24"
}

variable "cluster_name" {}
