locals {
  env    = "${terraform.workspace}"
  region = "eu-west-1"
}

terraform {
  required_version = ">= 0.11.0"
}

provider "aws" {
  region  = "${local.region}"
  version = "~> 1.24"
}

provider "null" {
  version = "~> 1.0"
}

provider "random" {
  version = "~> 2.0"
}

data "aws_region" "current" {
  name = "${local.region}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source     = "./vpc"
  cidr_block = "${var.vpc_cidr}"
  azs        = "${slice(data.aws_availability_zones.available.names, 0, 3)}"
  aws_region = "${data.aws_region.current.name}"
}

module "elb" {
  source     = "./elb"
  vpc_id     = "${module.vpc.vpc_id}"
  subnet_ids = "${module.vpc.public_subnet_ids}"
}

module "etcd" {
  source       = "./etcd"
  vpc_id       = "${module.vpc.vpc_id}"
  vpc_cidr     = "${var.vpc_cidr}"
  key_name     = "tmuntaner"
  subnet_ids   = "${module.vpc.public_subnet_ids}"
  cluster_name = "${var.cluster_name}"
}
