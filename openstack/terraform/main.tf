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

resource "random_pet" "cluster_name" {}

module "network" {
  source              = "./network"
  subnet_cidr         = "${var.subnet_cidr}"
  cluster_name        = "${random_pet.cluster_name.id}"
  external_network_id = "${var.external_network_id}"
}

resource "openstack_compute_secgroup_v2" "terraform" {
  name        = "terraform"
  description = "Security group for the Terraform example instances"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 80
    to_port     = 80
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    cidr        = "0.0.0.0/0"
  }
}

resource "openstack_compute_instance_v2" "caasp_admin" {
  name            = "${random_pet.cluster_name.id}-caasp-admin"
  flavor_name     = "m1.large"
  key_pair        = "${var.keypair}"
  security_groups = ["${openstack_compute_secgroup_v2.terraform.id}"]

  block_device {
    uuid                  = "a588e1cd-df27-4861-8cf5-95c9b01f8939"
    source_type           = "image"
    volume_size           = 40
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  network {
    name = "${module.network.network_name}"
  }
}

resource "openstack_networking_floatingip_v2" "caasp_worker" {
  count = 1
  pool  = "floating"
}

resource "openstack_compute_floatingip_associate_v2" "caasp_worker" {
  count                 = 1
  floating_ip           = "${element(openstack_networking_floatingip_v2.caasp_worker.*.address, count.index)}"
  instance_id           = "${element(openstack_compute_instance_v2.caasp_admin.*.id, count.index)}"
  fixed_ip              = "${element(openstack_compute_instance_v2.caasp_admin.*.network.0.fixed_ip_v4, count.index)}"
  wait_until_associated = true
}
