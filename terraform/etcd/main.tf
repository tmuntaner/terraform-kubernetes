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

module "etcd_node_1" {
  source            = "./etcd_node"
  node_id           = 1
  key_name          = "tmuntaner"
  subnet_id         = "${var.subnet_ids[0]}"
  cluster_name      = "${var.cluster_name}"
  ami_id            = "${data.aws_ami.etcd.id}"
  security_group_id = "${aws_security_group.main.id}"
}

module "etcd_node_2" {
  source            = "./etcd_node"
  node_id           = 2
  key_name          = "tmuntaner"
  subnet_id         = "${var.subnet_ids[0]}"
  cluster_name      = "${var.cluster_name}"
  ami_id            = "${data.aws_ami.etcd.id}"
  security_group_id = "${aws_security_group.main.id}"
}

module "etcd_node_3" {
  source            = "./etcd_node"
  node_id           = 3
  key_name          = "tmuntaner"
  subnet_id         = "${var.subnet_ids[0]}"
  cluster_name      = "${var.cluster_name}"
  ami_id            = "${data.aws_ami.etcd.id}"
  security_group_id = "${aws_security_group.main.id}"
}
