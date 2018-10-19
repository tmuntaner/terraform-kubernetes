# kube-proxy

cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "system:node-proxier",
      "OU": "Kubernetes",
      "ST": "Bayern"
    }
  ]
}
EOF

cfssl gencert \
  -ca=data/keys/ca.pem \
  -ca-key=data/keys/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

rm kube-proxy-csr.json kube-proxy.csr
mv kube-proxy.pem data/keys
mv kube-proxy-key.pem data/keys

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=data/keys/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_INTERNAL_ADDRESS}:6443 \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=data/keys/kube-proxy.pem \
  --client-key=data/keys/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

mv kube-proxy.kubeconfig data/config
