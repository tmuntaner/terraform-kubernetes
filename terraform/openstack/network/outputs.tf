output "network_name" {
  value = "${openstack_networking_network_v2.main.name}"
}

output "subnet_id" {
  value = "${openstack_networking_subnet_v2.main.id}"
}

output "router_id" {
  value = "${openstack_networking_router_v2.main.id}"
}
