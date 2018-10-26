resource "openstack_compute_secgroup_v2" "main" {
  name        = "${var.cluster_name}-kubernetes-worker"
  description = "kubernetes worker"

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
  name            = "${var.cluster_name}-kubernetes-worker-${count.index}"
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
    fixed_ip_v4 = "10.240.8.2${count.index}"
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

resource "null_resource" "config_base" {
  triggers = {}

  provisioner "local-exec" {
    command = <<CMD
cd ../../
./scripts/worker-base.sh
CMD

    environment {
      KUBERNETES_INTERNAL_ADDRESS = "${var.kubernetes_internal_address}"
    }
  }
}

resource "null_resource" "config" {
  count = "${var.instance_count}"

  triggers = {
    host_id = "${element(openstack_compute_instance_v2.main.*.id, count.index)}"
  }

  provisioner "local-exec" {
    command = <<CMD
cd ../../
./scripts/worker.sh
CMD

    environment {
      instance                    = "worker-${count.index}"
      instance_ip                 = "${element(openstack_compute_instance_v2.main.*.network.0.fixed_ip_v4, count.index)}"
      instance_hostname           = "${element(openstack_compute_instance_v2.main.*.name, count.index)}"
      KUBERNETES_INTERNAL_ADDRESS = "${var.kubernetes_internal_address}"
    }
  }
}

resource "null_resource" "provision" {
  count      = "${var.instance_count}"
  depends_on = ["null_resource.config", "null_resource.config_base"]

  connection {
    host = "${element(openstack_compute_floatingip_associate_v2.main.*.floating_ip, count.index)}"
    user = "opensuse"
  }

  triggers {
    host_id        = "${element(openstack_compute_instance_v2.main.*.id, count.index)}"
    config_id      = "${element(null_resource.config.*.id, count.index)}"
    config_base_id = "${null_resource.config_base.id}"
  }

  provisioner "file" {
    source      = "../../data/keys/ca.pem"
    destination = "ca.pem"
  }

  provisioner "file" {
    source      = "../../cloud.conf"
    destination = "cloud-config.conf"
  }

  provisioner "file" {
    source      = "../../cloud-trust.pem"
    destination = "cloud-trust.pem"
  }

  provisioner "file" {
    source      = "../../data/config/cloud-controller-manager.kubeconfig"
    destination = "cloud-controller-manager.kubeconfig"
  }

  provisioner "file" {
    source      = "../../data/keys/worker-${count.index}-key.pem"
    destination = "worker-${count.index}-key.pem"
  }

  provisioner "file" {
    source      = "../../data/keys/worker-${count.index}.pem"
    destination = "worker-${count.index}.pem"
  }

  provisioner "file" {
    source      = "../../data/config/worker-${count.index}.kubeconfig"
    destination = "worker-${count.index}.kubeconfig"
  }

  provisioner "file" {
    source      = "../../data/config/kube-proxy.kubeconfig"
    destination = "kube-proxy.kubeconfig"
  }

  # containerd
  # TODO: move to packer
  provisioner "remote-exec" {
    inline = [
      "sudo mv ca.pem /var/lib/kubernetes/",
      "sudo mkdir -p /etc/containerd/",
      "sudo mv worker-${count.index}-key.pem worker-${count.index}.pem /var/lib/kubelet/",
      "sudo mv worker-${count.index}.kubeconfig /var/lib/kubelet/kubeconfig",
      "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig",
      "sudo mkdir /etc/cloud",
      "sudo mv cloud-config.conf cloud-trust.pem /etc/cloud/",
      "sudo mkdir /etc/kubernetes",
      "sudo mv cloud-controller-manager.kubeconfig /etc/kubernetes/cloud-controller-manager.kubeconfig",
    ]
  }

  provisioner "local-exec" {
    command = <<CMD
ansible-playbook -i $NODE_IP, -u opensuse -s playbook-worker.yml -e worker_index="$WORKER_INDEX"
CMD

    working_dir = "../../ansible"

    environment {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      WORKER_INDEX              = "${count.index}"
      NODE_IP                   = "${element(openstack_networking_floatingip_v2.main.*.address, count.index)}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl daemon-reload",
      "sudo systemctl enable containerd kubelet kube-proxy",
      "sudo systemctl restart containerd kubelet kube-proxy",
    ]
  }
}
