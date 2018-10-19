locals {
  fixed_ips = "${formatlist("%v", aws_instance.etcd.*.public_ip)}"
}

resource "aws_security_group" "main" {
  name        = "${terraform.workspace}-kubernetes-cluster-etcd"
  description = "Kubernetes Cluster Security Group"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${terraform.workspace}-kubernetes-cluster"
  }
}

data "aws_ami" "etcd" {
  most_recent = true

  filter {
    name   = "name"
    values = ["leap-42-3-etcd"]
  }

  owners = ["374278911799"]
}

data "template_file" "ip_address" {
  count    = 3
  template = "10.240.$${subnet}.10"

  vars {
    subnet = "${8 * (count.index + 1)}"
  }
}

resource "aws_instance" "etcd" {
  count                  = 3
  ami                    = "${data.aws_ami.etcd.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${var.subnet_ids[count.index]}"
  vpc_security_group_ids = ["${aws_security_group.main.id}"]
  private_ip             = "${element(data.template_file.ip_address.*.rendered, count.index)}"
  key_name               = "${var.key_name}"

  lifecycle {
    ignore_changes = ["ami"]
  }

  tags {
    Name = "${var.cluster_name}-etcd-${count.index}"
  }
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
  depends_on = ["null_resource.certs"]

  triggers {
    host_id = "${element(aws_instance.etcd.*.id, count.index)}"
  }

  connection {
    host = "${element(aws_instance.etcd.*.public_ip, count.index)}"
    user = "ec2-user"
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
ansible-playbook -i $ETCD_IP, -u ec2-user -s playbook-etcd.yml -e etcd_node_name=$ETCD_NODE_NAME -e etcd_initial_cluster="$ETCD_INITIAL_CLUSTER"
CMD

    working_dir = "../../ansible"

    environment {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ETCD_IP                   = "${element(aws_instance.etcd.*.public_ip, count.index)}"
      ETCD_INITIAL_CLUSTER      = "ip-10-240-8-10=https://10.240.8.10:2380,ip-10-240-16-10=https://10.240.16.10:2380,ip-10-240-24-10=https://10.240.24.10:2380"
      ETCD_NODE_NAME            = "ip-${replace(element(data.template_file.ip_address.*.rendered, count.index), ".", "-")}"
    }
  }
}
