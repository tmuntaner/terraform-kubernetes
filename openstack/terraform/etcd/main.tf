resource "openstack_compute_secgroup_v2" "etcd" {
  name        = "${var.cluster_name}-kubernetes-etcd"
  description = "kubernetes etcd"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 2380
    to_port     = 2380
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 2379
    to_port     = 2379
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

resource "openstack_compute_instance_v2" "etcd" {
  count           = 3
  name            = "${var.cluster_name}-etcd"
  flavor_name     = "m1.large"
  key_pair        = "${var.keypair}"
  security_groups = ["${openstack_compute_secgroup_v2.etcd.name}"]

  block_device {
    uuid                  = "25cfaac8-1e51-450c-af25-7423cca43677"
    source_type           = "image"
    volume_size           = 40
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  network {
    name        = "${var.network_name}"
    fixed_ip_v4 = "10.240.8.1${count.index}"
  }
}

resource "openstack_networking_floatingip_v2" "etcd" {
  count = 3
  pool  = "floating"
}

resource "openstack_compute_floatingip_associate_v2" "etcd" {
  count                 = 3
  floating_ip           = "${element(openstack_networking_floatingip_v2.etcd.*.address, count.index)}"
  instance_id           = "${element(openstack_compute_instance_v2.etcd.*.id, count.index)}"
  fixed_ip              = "${element(openstack_compute_instance_v2.etcd.*.network.0.fixed_ip_v4, count.index)}"
  wait_until_associated = true
}

resource "null_resource" "provision" {
  count = 3

  connection {
    host = "${element(openstack_compute_floatingip_associate_v2.etcd.*.floating_ip, count.index)}"
    user = "opensuse"
  }

  triggers {
    host_id = "${element(openstack_compute_instance_v2.etcd.*.id, count.index)}"
  }

  provisioner "file" {
    source      = "tmp/ca.pem"
    destination = "ca.pem"
  }

  provisioner "file" {
    source      = "tmp/kubernetes-key.pem"
    destination = "kubernetes-key.pem"
  }

  provisioner "file" {
    source      = "tmp/kubernetes.pem"
    destination = "kubernetes.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/",
    ]
  }

  provisioner "local-exec" {
    command = <<CMD
ansible-playbook -i $ETCD_IP, -u opensuse -s playbook.yml -e etcd_node_name=$ETCD_NODE_NAME -e etcd_initial_cluster="$ETCD_INITIAL_CLUSTER"
CMD

    working_dir = "../../ansible"

    environment {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ETCD_IP                   = "${element(openstack_networking_floatingip_v2.etcd.*.address, count.index)}"
      ETCD_INITIAL_CLUSTER      = "ip-10-240-8-10=https://10.240.8.10:2380,ip-10-240-8-11=https://10.240.8.11:2380,ip-10-240-8-12=https://10.240.8.12:2380"
      ETCD_NODE_NAME            = "ip-${replace(element(openstack_compute_instance_v2.etcd.*.network.0.fixed_ip_v4, count.index), ".", "-")}"
    }
  }
}
