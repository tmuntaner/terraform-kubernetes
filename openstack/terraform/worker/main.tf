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
    uuid                  = "02fd282d-f755-4a66-b5de-eb7cf117e927"
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
  count    = "${var.instance_count}"
  triggers = {}

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
      "sudo systemctl restart containerd kubelet kube-proxy",
    ]
  }
}

resource "openstack_networking_router_route_v2" "router_route_1" {
  count            = "${var.instance_count}"
  router_id        = "${var.router_id}"
  destination_cidr = "10.200.${count.index}.0/24"
  next_hop         = "${element(openstack_compute_instance_v2.main.*.network.0.fixed_ip_v4, count.index)}"
}
