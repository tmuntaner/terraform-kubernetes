locals {
  fixed_ips       = ["10.240.8.10", "10.240.8.11", "10.240.8.12"]
  etcd_nodes      = "${formatlist("%v", data.template_file.etcd_node.*.rendered)}"
  etcd_node_names = "${formatlist("%v", data.template_file.etcd_node_name.*.rendered)}"
}

data "template_file" "etcd_node_name" {
  count    = 3
  template = "ip-$${clean_ip}"

  vars {
    clean_ip = "${replace(element(local.fixed_ips, count.index), ".", "-")}"
  }
}

data "template_file" "etcd_node" {
  count    = 3
  template = "$${etcd_node_name}=https://$${etcd_ip}:2380"

  vars {
    etcd_node_name = "${element(local.etcd_node_names, count.index)}"
    etcd_ip        = "${element(local.fixed_ips, count.index)}"
  }
}

resource "openstack_compute_secgroup_v2" "etcd" {
  name        = "${terraform.workspace}-kubernetes-etcd"
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

resource "openstack_compute_instance_v2" "main" {
  count           = 3
  name            = "${terraform.workspace}-kubernetes-etcd-${count.index}"
  flavor_name     = "m1.large"
  key_pair        = "${var.keypair}"
  security_groups = ["${openstack_compute_secgroup_v2.etcd.name}"]
  image_id        = "${var.image_id}"

  network {
    name        = "${var.network_name}"
    fixed_ip_v4 = "${element(local.fixed_ips, count.index)}"
  }
}

// ansible will mount /dev/vdb to /var/lib/etcd
resource "openstack_compute_volume_attach_v2" "data" {
  count       = 3
  instance_id = "${openstack_compute_instance_v2.main.*.id[count.index]}"
  volume_id   = "${var.etcd_data_volumes[count.index]}"
  device      = "/dev/vdb"
}

resource "openstack_networking_floatingip_v2" "main" {
  count = 3
  pool  = "floating"
}

resource "openstack_compute_floatingip_associate_v2" "main" {
  count                 = 3
  floating_ip           = "${openstack_networking_floatingip_v2.main.*.address[count.index]}"
  instance_id           = "${openstack_compute_instance_v2.main.*.id[count.index]}"
  fixed_ip              = "${openstack_compute_instance_v2.main.*.network.0.fixed_ip_v4[count.index]}"
  wait_until_associated = true
}

resource "null_resource" "certs" {
  provisioner "local-exec" {
    command = <<CMD
cd ../../
./scripts/etcd.sh
CMD

    environment {
      ETCD_HOSTS = "${join(",", local.fixed_ips)}"
    }
  }
}

resource "null_resource" "provision" {
  count      = 3
  depends_on = ["null_resource.certs", "openstack_compute_volume_attach_v2.data"]

  connection {
    host = "${openstack_compute_floatingip_associate_v2.main.*.floating_ip[count.index]}"
    user = "sles"
  }

  triggers {
    host_id = "${openstack_compute_instance_v2.main.*.id[count.index]}"
  }

  provisioner "file" {
    source      = "../../data/keys/ca.pem"
    destination = "ca.pem"
  }

  // TODO: change to etcd-key.pem (let's not break aws yet)
  provisioner "file" {
    source      = "../../data/keys/etcd-key.pem"
    destination = "kubernetes-key.pem"
  }

  // TODO: change to etcd.pem (let's not break aws yet)
  provisioner "file" {
    source      = "../../data/keys/etcd.pem"
    destination = "kubernetes.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/",
    ]
  }

  provisioner "local-exec" {
    command = <<CMD
ansible-playbook -i $NODE_IP, -u sles -s playbook-etcd.yml -e etcd_node_name=$ETCD_NODE_NAME -e etcd_initial_cluster="$ETCD_INITIAL_CLUSTER"
CMD

    working_dir = "../../ansible"

    environment {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      NODE_IP                   = "${element(openstack_networking_floatingip_v2.main.*.address, count.index)}"
      ETCD_INITIAL_CLUSTER      = "${join(",", local.etcd_nodes)}"
      ETCD_NODE_NAME            = "${element(local.etcd_node_names, count.index)}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl restart etcd",
    ]
  }
}
