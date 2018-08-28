data "aws_region" "current" {}

# ELB

resource "aws_security_group" "elb_api" {
  vpc_id = "${var.vpc_id}"

  lifecycle {
    create_before_destroy = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "api_internal" {
  name            = "kubernetes-api-internal"
  subnets         = ["${var.subnet_ids}"]
  internal        = true
  security_groups = ["${aws_security_group.elb_api.id}"]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    target              = "HTTP:80/healthz"
  }
}

resource "aws_elb" "api_public" {
  name            = "kubernetes-api-public"
  subnets         = ["${var.subnet_ids}"]
  internal        = false
  security_groups = ["${aws_security_group.elb_api.id}"]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    target              = "HTTP:80/healthz"
  }
}

resource "null_resource" "generate_config" {
  provisioner "local-exec" {
    command = <<CMD
rm -f tmp/*.pem tmp/*.csr tmp/*.json tmp/*.kubeconfig admin.kubeconfig
cd tmp
../scripts/certs.sh
../scripts/server_kubectl.sh
cd ..
./scripts/user_kubectl.sh
CMD

    environment {
      KUBERNETES_INTERNAL_ADDRESS = "${aws_elb.api_internal.dns_name}"
      KUBERNETES_PUBLIC_ADDRESS   = "${aws_elb.api_public.dns_name}"
    }
  }
}

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

data "aws_ami" "controller" {
  most_recent = true

  filter {
    name   = "name"
    values = ["leap-42-3-kubernetes-controller"]
  }

  owners = ["374278911799"]
}

data "aws_ami" "worker" {
  most_recent = true

  filter {
    name   = "name"
    values = ["leap-42-3-kubernetes-worker"]
  }

  owners = ["374278911799"]
}

resource "aws_instance" "etcd" {
  count                  = 3
  ami                    = "${data.aws_ami.etcd.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${var.subnet_ids[0]}"
  vpc_security_group_ids = ["${aws_security_group.main.id}"]
  private_ip             = "10.240.8.1${count.index}"
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
  --name ip-10-240-8-1${count.index} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://10.240.8.1${count.index}:2380 \\
  --listen-peer-urls https://10.240.8.1${count.index}:2380 \\
  --listen-client-urls https://10.240.8.1${count.index}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://10.240.8.1${count.index}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ip-10-240-8-10=https://10.240.8.10:2380,ip-10-240-8-11=https://10.240.8.11:2380,ip-10-240-8-12=https://10.240.8.12:2380 \\
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

  tags {
    Name = "etcd-${count.index}"
  }
}

resource "aws_instance" "controller" {
  count                  = 3
  ami                    = "${data.aws_ami.controller.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${var.subnet_ids[0]}"
  vpc_security_group_ids = ["${aws_security_group.main.id}"]
  private_ip             = "10.240.8.3${count.index}"
  key_name               = "${var.key_name}"

  connection {
    user = "ec2-user"
  }

  provisioner "file" {
    source      = "tmp/ca.pem"
    destination = "ca.pem"
  }

  provisioner "file" {
    source      = "tmp/ca-key.pem"
    destination = "ca-key.pem"
  }

  provisioner "file" {
    source      = "tmp/kubernetes-key.pem"
    destination = "kubernetes-key.pem"
  }

  provisioner "file" {
    source      = "tmp/kubernetes.pem"
    destination = "kubernetes.pem"
  }

  provisioner "file" {
    source      = "tmp/service-account-key.pem"
    destination = "service-account-key.pem"
  }

  provisioner "file" {
    source      = "tmp/service-account.pem"
    destination = "service-account.pem"
  }

  provisioner "file" {
    source      = "tmp/admin.kubeconfig"
    destination = "admin.kubeconfig"
  }

  provisioner "file" {
    source      = "tmp/kube-controller-manager.kubeconfig"
    destination = "kube-controller-manager.kubeconfig"
  }

  provisioner "file" {
    source      = "tmp/kube-scheduler.kubeconfig"
    destination = "kube-scheduler.kubeconfig"
  }

  # todo: add encryption key to vault
  # head -c 32 /dev/urandom | base64
  provisioner "file" {
    source      = "config/encryption-config.yaml"
    destination = "encryption-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem encryption-config.yaml /var/lib/kubernetes/",
      <<CAT
cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=10.240.8.3${count.index} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.8.10:2379,https://10.240.8.11:2379,https://10.240.8.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      CAT
      ,
      "sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/",
      <<CAT
cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      CAT
      ,
      "sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/",
      <<CAT
cat <<EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF
      CAT
      ,
      <<CAT
      cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      CAT
      ,
      "sudo systemctl daemon-reload",
      "sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler",
      "sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler",
    ]
  }

  tags {
    Name = "controller-${count.index}"
  }
}

resource "aws_instance" "worker" {
  count                  = 3
  ami                    = "${data.aws_ami.worker.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${var.subnet_ids[0]}"
  vpc_security_group_ids = ["${aws_security_group.main.id}"]
  private_ip             = "10.240.8.2${count.index}"
  key_name               = "${var.key_name}"

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
    Name = "worker-${count.index}"
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

resource "aws_elb_attachment" "api_internal" {
  count    = 3
  elb      = "${aws_elb.api_internal.id}"
  instance = "${element(aws_instance.controller.*.id, count.index)}"
}

resource "aws_elb_attachment" "api_public" {
  count    = 3
  elb      = "${aws_elb.api_public.id}"
  instance = "${element(aws_instance.controller.*.id, count.index)}"
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
