output "kubernetes_api_public_ip" {
  value = "${openstack_networking_floatingip_v2.kubernetes_api.address}"
}

output "kubernetes_api_private_ip" {
  value = "${openstack_lb_loadbalancer_v2.kubernetes_lb.vip_address}"
}
