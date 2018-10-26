cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance_hostname}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "system:nodes",
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
    -hostname=${instance_hostname},${instance_ip} \
    -profile=kubernetes \
    ${instance}-csr.json | cfssljson -bare ${instance}

rm ${instance}-csr.json ${instance}.csr
mv ${instance}.pem data/keys
mv ${instance}-key.pem data/keys

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=data/keys/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_INTERNAL_ADDRESS}:6443 \
  --kubeconfig=${instance}.kubeconfig

kubectl config set-credentials system:node:${instance} \
  --client-certificate=data/keys/${instance}.pem \
  --client-key=data/keys/${instance}-key.pem \
  --embed-certs=true \
  --kubeconfig=${instance}.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:node:${instance} \
  --kubeconfig=${instance}.kubeconfig

kubectl config use-context default --kubeconfig=${instance}.kubeconfig
mv ${instance}.kubeconfig data/config

# Cloud Controller Manager

cat > cloud-controller-manager-csr.json <<EOF
{
  "CN": "system:cloud-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "cloud-controller-manager",
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
  cloud-controller-manager-csr.json | cfssljson -bare cloud-controller-manager

rm cloud-controller-manager-csr.json cloud-controller-manager.csr
mv cloud-controller-manager-key.pem data/keys
mv cloud-controller-manager.pem data/keys

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=data/keys/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_INTERNAL_ADDRESS}:6443 \
  --kubeconfig=cloud-controller-manager.kubeconfig

kubectl config set-credentials cloud-controller-manager \
  --client-certificate=data/keys/kube-controller-manager.pem \
  --client-key=data/keys/cloud-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=cloud-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=cloud-controller-manager \
  --kubeconfig=cloud-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=cloud-controller-manager.kubeconfig
mv cloud-controller-manager.kubeconfig data/config
