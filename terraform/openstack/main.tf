terraform {
  required_version = ">= 0.11.0"

  backend "s3" {
    bucket  = "suse-scc-terraform-state"
    key     = "kubernetes/tmuntaner.tfstate"
    region  = "eu-central-1"
    encrypt = "true"
  }
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
  external_network_id = "${var.external_network_id}"
}

module "etcd" {
  source            = "./etcd"
  keypair           = "${var.keypair}"
  network_name      = "${module.network.network_name}"
  etcd_data_volumes = ["${var.etcd_data_volume_1}", "${var.etcd_data_volume_2}", "${var.etcd_data_volume_3}"]
  image_id          = "${var.etcd_image_id}"
}

module "controller" {
  source                       = "./controller"
  keypair                      = "${var.keypair}"
  network_name                 = "${module.network.network_name}"
  etcd_instance_ip_addresses   = "${module.etcd.etcd_instance_ip_addresses}"
  subnet_id                    = "${module.network.subnet_id}"
  image_id                     = "${var.controller_image_id}"
  kubernetes_encryption_secret = "${var.kubernetes_encryption_secret}"
}

module "worker" {
  source                      = "./worker"
  keypair                     = "${var.keypair}"
  network_name                = "${module.network.network_name}"
  router_id                   = "${module.network.router_id}"
  subnet_id                   = "${module.network.subnet_id}"
  kubernetes_internal_address = "${module.controller.kubernetes_api_public_ip}"
  image_id                    = "${var.worker_image_id}"
}
