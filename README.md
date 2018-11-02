# Kubernetes with Terraform Playground

**Prerequisites:**

- Install Cloudflare's PKI and TLS Toolkit [CFSSL](https://github.com/cloudflare/cfssl).

```bash
go get -u github.com/cloudflare/cfssl/cmd/cfssl
go get -u github.com/cloudflare/cfssl/cmd/cfssljson
```

**Create the container volumes:**

The lifecycle of the etcd data volume is controlled outside of terraform. Create three volumes, around 10GB each, in openstack and take note of their ids.

**Attach the volumes to a server to format them:**

Use `fdisk` to see the attached drives so that we know what to format:

```bash
sudo fdisk -l
```

```text
Disk /dev/vda: 20 GiB, 21474836480 bytes, 41943040 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x4b5e14ea

Device     Boot Start      End  Sectors Size Id Type
/dev/vda1  *     2048 41943006 41940959  20G 83 Linux


Disk /dev/vdb: 10 GiB, 10737418240 bytes, 20971520 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/vdc: 10 GiB, 10737418240 bytes, 20971520 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes


Disk /dev/vdd: 10 GiB, 10737418240 bytes, 20971520 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
```

We can see that our drives are `/dev/vdb`, `/dev/vdc`, and `/dev/vdd`.

**Format the drives:**

```bash
sudo mkfs.ext4 /dev/vdb
sudo mkfs.ext4 /dev/vdc
sudo mkfs.ext4 /dev/vdd
```

**Run after cluster is created:**

```bash
kubectl apply --kubeconfig admin.kubeconfig -f manifests/cluster-roles.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/flannel.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/dns.yaml
```

## Helm

```bash
kubectl apply --kubeconfig admin.kubeconfig -f manifests/helm-rbac-config.yaml
helm init --service-account tiller
```

## Openstack Cloud Controller

```bash
kubectl apply --kubeconfig admin.kubeconfig -f manifests/cloud-controller-openstack.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/csi-provisioner.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/csi-nodeplugin.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/csi-attacher.yaml
```

## Nginx Ingress

```bash
kubectl apply --kubeconfig admin.kubeconfig -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/nginx-ingress.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/example-ingress.yaml
```

## Prometheus

```bash
helm install stable/prometheus-operator --name prometheus-operator --namespace monitoring -f helm-config/prometheus.yaml
```

To Delete:

```bash
helm delete prometheus-operator
kubectl delete crd prometheuses.monitoring.coreos.com
kubectl delete crd prometheusrules.monitoring.coreos.com
kubectl delete crd servicemonitors.monitoring.coreos.com
kubectl delete crd alertmanagers.monitoring.coreos.com
```

## Kubernetes Dashboard

```bash
helm install stable/kubernetes-dashboard --name kubernetes-dashboard --namespace kubernetes-dashboard -f helm-config/kubernetes-dashboard.yaml
```
