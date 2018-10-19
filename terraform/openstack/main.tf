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

provider "template" {
  version = "~> 1.0"
}

module "network" {
  source              = "./network"
  subnet_cidr         = "${var.subnet_cidr}"
  cluster_name        = "${var.cluster_name}"
  external_network_id = "${var.external_network_id}"
}

module "etcd" {
  source       = "./etcd"
  cluster_name = "${var.cluster_name}"
  keypair      = "${var.keypair}"
  network_name = "${module.network.network_name}"
}

module "controller" {
  source                     = "./controller"
  cluster_name               = "${var.cluster_name}"
  keypair                    = "${var.keypair}"
  network_name               = "${module.network.network_name}"
  etcd_instance_ip_addresses = "${module.etcd.etcd_instance_ip_addresses}"
  subnet_id                  = "${module.network.subnet_id}"
}

module "worker" {
  source                      = "./worker"
  cluster_name                = "${var.cluster_name}"
  keypair                     = "${var.keypair}"
  network_name                = "${module.network.network_name}"
  router_id                   = "${module.network.router_id}"
  subnet_id                   = "${module.network.subnet_id}"
  kubernetes_internal_address = "${module.controller.kubernetes_api_public_ip}"
}
