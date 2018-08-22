locals {
  env    = "${terraform.workspace}"
  region = "eu-central-1"
}

terraform {
  required_version = ">= 0.11.0"
}

provider "aws" {
  region  = "${local.region}"
  version = "~> 1.24"
}

provider "null" {}

data "aws_region" "current" {
  name = "${local.region}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source     = "./vpc"
  cidr_block = "${var.vpc_cidr}"
  azs        = "${slice(data.aws_availability_zones.available.names, 0, 2)}"
  aws_region = "${data.aws_region.current.name}"
}

module "cluster" {
  source     = "./cluster"
  azs        = "${slice(data.aws_availability_zones.available.names, 0, 2)}"
  vpc_id     = "${module.vpc.vpc_id}"
  vpc_cidr   = "${var.vpc_cidr}"
  key_name   = "tmuntaner"
  subnet_ids = "${module.vpc.public_subnet_ids}"
  gateway_id = "${module.vpc.gateway_id}"
}
