resource "openstack_compute_secgroup_v2" "main" {
  name        = "${var.cluster_name}-kubernetes-controller"
  description = "kubernetes etcd"

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
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    cidr        = "0.0.0.0/0"
  }
}

resource "openstack_compute_instance_v2" "main" {
  count           = 3
  name            = "${var.cluster_name}-kubernetes-controller-${count.index}"
  flavor_name     = "m1.large"
  key_pair        = "${var.keypair}"
  security_groups = ["${openstack_compute_secgroup_v2.main.name}"]

  block_device {
    uuid                  = "27ce27e5-5fea-4f25-b2a0-c65de81572e3"
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
  count = 3
  pool  = "floating"
}

resource "openstack_compute_floatingip_associate_v2" "main" {
  count                 = 3
  floating_ip           = "${element(openstack_networking_floatingip_v2.main.*.address, count.index)}"
  instance_id           = "${element(openstack_compute_instance_v2.main.*.id, count.index)}"
  fixed_ip              = "${element(openstack_compute_instance_v2.main.*.network.0.fixed_ip_v4, count.index)}"
  wait_until_associated = true
}

resource "null_resource" "certs" {
  provisioner "local-exec" {
    command = <<CMD
cd ../../
./scripts/controller.sh
CMD
  }
}

resource "null_resource" "provision" {
  count      = 3
  depends_on = ["null_resource.certs"]

  connection {
    host = "${element(openstack_compute_floatingip_associate_v2.main.*.floating_ip, count.index)}"
    user = "opensuse"
  }

  triggers {
    host_id = "${element(openstack_compute_instance_v2.main.*.id, count.index)}"
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
ansible-playbook -i $NODE_IP, -u opensuse -s playbook-controller.yml
CMD

    working_dir = "../../ansible"

    environment {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      NODE_IP                   = "${element(openstack_networking_floatingip_v2.main.*.address, count.index)}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl restart kube-apiserver kube-controller-manager kube-scheduler",
    ]
  }
}
