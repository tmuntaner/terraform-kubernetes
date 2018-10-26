locals {
  fixed_ips  = "${formatlist("%v", openstack_compute_instance_v2.main.*.network.0.fixed_ip_v4)}"
  etcd_nodes = "${formatlist("%v", data.template_file.etcd_node.*.rendered)}"
}

resource "openstack_compute_secgroup_v2" "main" {
  name        = "${var.cluster_name}-kubernetes-controller"
  description = "kubernetes controller"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "udp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    cidr        = "0.0.0.0/0"
  }
}

resource "openstack_compute_instance_v2" "main" {
  count           = "${var.instance_count}"
  name            = "${var.cluster_name}-kubernetes-controller-${count.index}"
  flavor_name     = "m1.large"
  key_pair        = "${var.keypair}"
  security_groups = ["${openstack_compute_secgroup_v2.main.name}"]

  block_device {
    uuid                  = "${var.image_id}"
    source_type           = "image"
    volume_size           = 40
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  network {
    name        = "${var.network_name}"
    fixed_ip_v4 = "10.240.8.3${count.index}"
  }
}

resource "openstack_networking_floatingip_v2" "main" {
  count = "${var.instance_count}"
  pool  = "floating"
}

resource "openstack_compute_floatingip_associate_v2" "main" {
  count                 = "${var.instance_count}"
  floating_ip           = "${element(openstack_networking_floatingip_v2.main.*.address, count.index)}"
  instance_id           = "${element(openstack_compute_instance_v2.main.*.id, count.index)}"
  fixed_ip              = "${element(openstack_compute_instance_v2.main.*.network.0.fixed_ip_v4, count.index)}"
  wait_until_associated = true
}

data "template_file" "etcd_node" {
  count    = "${var.instance_count}"
  template = "https://$${etcd_ip}:2379"

  vars {
    etcd_ip = "${element(var.etcd_instance_ip_addresses, count.index)}"
  }
}

resource "null_resource" "config" {
  triggers {
    lb_internal_ip = "${openstack_lb_loadbalancer_v2.kubernetes_lb.vip_address}"
    lb_public_ip   = "${openstack_networking_floatingip_v2.kubernetes_api.address}"
  }

  provisioner "local-exec" {
    command = <<CMD
cd ../../
./scripts/controller.sh
./scripts/user_kubectl.sh
CMD

    environment {
      CONTROLLER_HOSTS            = "${join(",", local.fixed_ips)}"
      KUBERNETES_PUBLIC_ADDRESS   = "${openstack_networking_floatingip_v2.kubernetes_api.address}"
      KUBERNETES_INTERNAL_ADDRESS = "${openstack_lb_loadbalancer_v2.kubernetes_lb.vip_address}"
    }
  }
}

resource "null_resource" "provision" {
  count      = "${var.instance_count}"
  depends_on = ["null_resource.config"]

  connection {
    host = "${element(openstack_compute_floatingip_associate_v2.main.*.floating_ip, count.index)}"
    user = "opensuse"
  }

  triggers {
    host_id   = "${element(openstack_compute_instance_v2.main.*.id, count.index)}"
    config_id = "${null_resource.config.id}"
  }

  provisioner "file" {
    source      = "../../data/keys/ca.pem"
    destination = "ca.pem"
  }

  provisioner "file" {
    source      = "../../data/keys/ca-key.pem"
    destination = "ca-key.pem"
  }

  provisioner "file" {
    source      = "../../data/keys/kubernetes-key.pem"
    destination = "kubernetes-key.pem"
  }

  provisioner "file" {
    source      = "../../data/keys/kubernetes.pem"
    destination = "kubernetes.pem"
  }

  provisioner "file" {
    source      = "../../data/keys/service-account-key.pem"
    destination = "service-account-key.pem"
  }

  provisioner "file" {
    source      = "../../data/keys/service-account.pem"
    destination = "service-account.pem"
  }

  provisioner "file" {
    source      = "../../data/config/admin.kubeconfig"
    destination = "admin.kubeconfig"
  }

  provisioner "file" {
    source      = "../../data/config/kube-controller-manager.kubeconfig"
    destination = "kube-controller-manager.kubeconfig"
  }

  provisioner "file" {
    source      = "../../data/config/kube-scheduler.kubeconfig"
    destination = "kube-scheduler.kubeconfig"
  }

  provisioner "file" {
    source      = "../../data/config/encryption-config.yaml"
    source      = "tmp/encryption-config.yaml"
    destination = "encryption-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem encryption-config.yaml /var/lib/kubernetes/",
      "sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/",
      "sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/",
    ]
  }

  provisioner "local-exec" {
    command = <<CMD
ansible-playbook -i $NODE_IP, -u opensuse -s playbook-controller.yml -e etcd_cluster="$ETCD_CLUSTER"
CMD

    working_dir = "../../ansible"

    environment {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ETCD_CLUSTER              = "${join(",", local.etcd_nodes)}"
      NODE_IP                   = "${element(openstack_networking_floatingip_v2.main.*.address, count.index)}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl restart kube-apiserver kube-controller-manager kube-scheduler",
    ]
  }
}

# Load Balancer

resource "openstack_networking_secgroup_v2" "kubernetes_lb" {
  name        = "${var.cluster_name}-kubernetes-lb"
  description = "Kubernetes Load Balancer Security Group"
}

resource "openstack_networking_secgroup_rule_v2" "kubernetes_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.kubernetes_lb.id}"
}

resource "openstack_networking_floatingip_v2" "kubernetes_api" {
  pool    = "floating"
  port_id = "${openstack_lb_loadbalancer_v2.kubernetes_lb.vip_port_id}"
}

resource "openstack_lb_loadbalancer_v2" "kubernetes_lb" {
  name               = "${var.cluster_name}-kubernetes"
  vip_subnet_id      = "${var.subnet_id}"
  security_group_ids = ["${openstack_networking_secgroup_v2.kubernetes_lb.id}"]
}

resource "openstack_lb_pool_v2" "kubernetes_api" {
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = "${openstack_lb_listener_v2.kubernetes_api.id}"
}

resource "openstack_lb_listener_v2" "kubernetes_api" {
  name            = "${var.cluster_name}-kubernetes-api-listener"
  protocol        = "TCP"
  protocol_port   = 6443
  loadbalancer_id = "${openstack_lb_loadbalancer_v2.kubernetes_lb.id}"
}

resource "openstack_lb_member_v2" "kubernetes_api" {
  count         = "${var.instance_count}"
  name          = "${var.cluster_name}-kubernetes-api-${count.index}"
  pool_id       = "${openstack_lb_pool_v2.kubernetes_api.id}"
  address       = "${element(openstack_compute_instance_v2.main.*.network.0.fixed_ip_v4, count.index)}"
  protocol_port = 6443
  subnet_id     = "${var.subnet_id}"
}
