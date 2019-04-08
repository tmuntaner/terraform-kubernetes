resource "openstack_networking_network_v2" "main" {
  name           = "${terraform.workspace}-kubernetes"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "main" {
  name       = "${terraform.workspace}-kubernetes"
  network_id = "${openstack_networking_network_v2.main.id}"
  cidr       = "${var.subnet_cidr}"
  ip_version = 4
}

resource "openstack_networking_router_v2" "main" {
  name                = "${terraform.workspace}-kubernetes"
  admin_state_up      = "true"
  external_network_id = "${var.external_network_id}"
}

resource "openstack_networking_router_interface_v2" "main" {
  router_id = "${openstack_networking_router_v2.main.id}"
  subnet_id = "${openstack_networking_subnet_v2.main.id}"
}
