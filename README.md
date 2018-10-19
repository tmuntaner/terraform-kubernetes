# Kubernetes with Terraform Playground

**Prerequisites:**

- Install Cloudflare's PKI and TLS Toolkit [CFSSL](https://github.com/cloudflare/cfssl).

```bash
go get -u github.com/cloudflare/cfssl/cmd/cfssl
go get -u github.com/cloudflare/cfssl/cmd/cfssljson
```

**Run after cluster is created:**

```bash
kubectl apply --kubeconfig admin.kubeconfig -f manifests/cluster-roles.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/flannel.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/dns.yaml
kubectl apply --kubeconfig admin.kubeconfig -f manifests/rbac-config.yaml
```
