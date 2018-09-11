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
  azs        = "${slice(data.aws_availability_zones.available.names, 0, 1)}"
  aws_region = "${data.aws_region.current.name}"
}

module "elb" {
  source     = "./elb"
  vpc_id     = "${module.vpc.vpc_id}"
  subnet_ids = "${module.vpc.public_subnet_ids}"
}

module "config" {
  source            = "./config"
  internal_dns_name = "${module.elb.internal_dns_name}"
  public_dns_name   = "${module.elb.public_dns_name}"
}

module "etcd" {
  source       = "./etcd"
  vpc_id       = "${module.vpc.vpc_id}"
  vpc_cidr     = "${var.vpc_cidr}"
  key_name     = "tmuntaner"
  subnet_ids   = "${module.vpc.public_subnet_ids}"
  depends_on   = ["null_resource.generate_config"]
  cluster_name = "${module.config.cluster_name}"
}

module "controller" {
  source          = "./controller"
  vpc_id          = "${module.vpc.vpc_id}"
  vpc_cidr        = "${var.vpc_cidr}"
  key_name        = "tmuntaner"
  subnet_ids      = "${module.vpc.public_subnet_ids}"
  internal_elb_id = "${module.elb.internal_elb_id}"
  public_elb_id   = "${module.elb.public_elb_id}"
  cluster_name    = "${module.config.cluster_name}"
}

module "worker" {
  source       = "./worker"
  azs          = "${slice(data.aws_availability_zones.available.names, 0, 1)}"
  vpc_id       = "${module.vpc.vpc_id}"
  vpc_cidr     = "${var.vpc_cidr}"
  key_name     = "tmuntaner"
  subnet_ids   = "${module.vpc.public_subnet_ids}"
  gateway_id   = "${module.vpc.gateway_id}"
  cluster_name = "${module.config.cluster_name}"
}
