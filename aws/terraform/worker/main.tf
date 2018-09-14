resource "aws_security_group" "main" {
  name        = "${terraform.workspace}-kubernetes-cluster"
  description = "Kubernetes Cluster Security Group"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.200.0.0/16"]
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

data "aws_ami" "worker" {
  most_recent = true

  filter {
    name   = "name"
    values = ["leap-42-3-kubernetes-worker"]
  }

  owners = ["374278911799"]
}

resource "aws_instance" "worker" {
  count                  = 3
  ami                    = "${data.aws_ami.worker.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${var.subnet_ids[0]}"
  vpc_security_group_ids = ["${aws_security_group.main.id}"]
  private_ip             = "10.240.8.2${count.index}"
  key_name               = "${var.key_name}"
  source_dest_check      = false

  connection {
    user = "ec2-user"
  }

  provisioner "file" {
    source      = "tmp/ca.pem"
    destination = "ca.pem"
  }

  provisioner "file" {
    source      = "tmp/worker-${count.index}-key.pem"
    destination = "worker-${count.index}-key.pem"
  }

  provisioner "file" {
    source      = "tmp/worker-${count.index}.pem"
    destination = "worker-${count.index}.pem"
  }

  provisioner "file" {
    source      = "tmp/worker-${count.index}.kubeconfig"
    destination = "worker-${count.index}.kubeconfig"
  }

  provisioner "file" {
    source      = "tmp/kube-proxy.kubeconfig"
    destination = "kube-proxy.kubeconfig"
  }

  tags {
    Name = "${var.cluster_name}-worker-${count.index}"
  }

  # CNI Networking
  provisioner "remote-exec" {
    inline = [
      <<CAT
cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "10.200.${count.index}.0/24"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF
      CAT
      ,
      <<CAT
cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF
    CAT
      ,
    ]
  }

  # containerd
  # TODO: move to packer
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/containerd/",
      <<CAT
cat << EOF | sudo tee /etc/containerd/config.toml
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"
EOF
    CAT
      ,
      <<CAT
cat <<EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
    CAT
      ,
    ]
  }

  # kubelet
  provisioner "remote-exec" {
    inline = [
      "sudo mv worker-${count.index}-key.pem worker-${count.index}.pem /var/lib/kubelet/",
      "sudo mv worker-${count.index}.kubeconfig /var/lib/kubelet/kubeconfig",
      "sudo mv ca.pem /var/lib/kubernetes/",
      <<CAT
cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "10.200.${count.index}.0/24"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/worker-${count.index}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/worker-${count.index}-key.pem"
EOF
      CAT
      ,
      <<CAT
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      CAT
      ,
    ]
  }

  # Kubernetes Proxy
  # TODO: move to packer
  provisioner "remote-exec" {
    inline = [
      "sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig",
      <<CAT
cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF
      CAT
      ,
      <<CAT
cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      CAT
      ,
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl daemon-reload",
      "sudo systemctl enable containerd kubelet kube-proxy",
      "sudo systemctl start containerd kubelet kube-proxy",
    ]
  }
}

resource "aws_route_table" "main" {
  vpc_id = "${var.vpc_id}"

  route {
    cidr_block  = "10.200.0.0/24"
    instance_id = "${element(aws_instance.worker.*.id, 0)}"
  }

  route {
    cidr_block  = "10.200.1.0/24"
    instance_id = "${element(aws_instance.worker.*.id, 1)}"
  }

  route {
    cidr_block  = "10.200.2.0/24"
    instance_id = "${element(aws_instance.worker.*.id, 2)}"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${var.gateway_id}"
  }

  tags {
    Name = "${terraform.env}-public-route-table"
  }
}

resource "aws_route_table_association" "main" {
  count = "${length(var.azs)}"

  subnet_id      = "${element(var.subnet_ids, count.index)}"
  route_table_id = "${aws_route_table.main.id}"
}
