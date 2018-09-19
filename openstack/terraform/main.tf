terraform {
  required_version = ">= 0.11.0"
}

provider "openstack" {
  version             = "~> 1.9"
  tenant_name         = "${var.openstack_tenant}"
  user_name           = "${var.openstack_username}"
  password            = "${var.openstack_password}"
  user_domain_name    = "ldap_users"
  project_domain_name = "default"
  auth_url            = "${var.openstack_auth_url}"
  region              = "CustomRegion"
}

provider "random" {
  version = "~> 2.0"
}

provider "null" {
  version = "~> 1.0"
}

resource "random_pet" "cluster_name" {}

module "network" {
  source              = "./network"
  subnet_cidr         = "${var.subnet_cidr}"
  cluster_name        = "${random_pet.cluster_name.id}"
  external_network_id = "${var.external_network_id}"
}

module "etcd" {
  source       = "./etcd"
  cluster_name = "${random_pet.cluster_name.id}"
  keypair      = "${var.keypair}"
  network_name = "${module.network.network_name}"
}

module "controller" {
  source       = "./controller"
  cluster_name = "${random_pet.cluster_name.id}"
  keypair      = "${var.keypair}"
  network_name = "${module.network.network_name}"
}
