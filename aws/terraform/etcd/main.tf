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

  connection {
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
      <<CAT
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ip-${replace(element(data.template_file.ip_address.*.rendered, count.index), ".", "-")} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${element(data.template_file.ip_address.*.rendered, count.index)}:2380 \\
  --listen-peer-urls https://${element(data.template_file.ip_address.*.rendered, count.index)}:2380 \\
  --listen-client-urls https://${element(data.template_file.ip_address.*.rendered, count.index)}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${element(data.template_file.ip_address.*.rendered, count.index)}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ip-10-240-8-10=https://10.240.8.10:2380,ip-10-240-16-10=https://10.240.16.10:2380,ip-10-240-24-10=https://10.240.24.10:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      CAT
      ,
      "sudo systemctl daemon-reload",
      "sudo systemctl enable etcd.service",
      "sudo systemctl start etcd.service",
    ]
  }

  lifecycle {
    ignore_changes = ["ami"]
  }

  tags {
    Name = "${var.cluster_name}-etcd-${count.index}"
  }
}
