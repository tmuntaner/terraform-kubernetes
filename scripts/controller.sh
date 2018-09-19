# api certificate

cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "Kubernetes",
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
  -hostname=10.240.8.30,10.240.8.31,10.240.8.32,${KUBERNETES_PUBLIC_ADDRESS},${KUBERNETES_INTERNAL_ADDRESS},127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

rm kubernetes-csr.json kubernetes.csr
mv kubernetes-key.pem data/keys
mv kubernetes.pem data/keys

# service account certificate

cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "Kubernetes",
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
  service-account-csr.json | cfssljson -bare service-account

rm service-account-csr.json service-account.csr
mv service-account-key.pem data/keys
mv service-account.pem data/keys

# encryption config

SECRET=`head -c 32 /dev/urandom | base64`

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${SECRET}
      - identity: {}
EOF

mv encryption-config.yaml data/config

# Admin config

cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "system:masters",
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
  admin-csr.json | cfssljson -bare admin

rm admin-csr.json admin.csr
mv admin-key.pem data/keys
mv admin.pem data/keys

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=data/keys/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=data/keys/admin.pem \
  --client-key=data/keys/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default --kubeconfig=admin.kubeconfig
mv admin.kubeconfig data/config

# Kube Controller Manager

cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "system:kube-controller-manager",
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
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

rm kube-controller-manager-csr.json kube-controller-manager.csr
mv kube-controller-manager-key.pem data/keys
mv kube-controller-manager.pem data/keys

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=data/keys/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=data/keys/kube-controller-manager.pem \
  --client-key=data/keys/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
mv kube-controller-manager.kubeconfig data/config

# Kube Scheduler

cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "system:kube-scheduler",
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
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

rm kube-scheduler-csr.json kube-scheduler.csr
mv kube-scheduler-key.pem data/keys
mv kube-scheduler.pem data/keys

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=data/keys/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=data/keys/kube-scheduler.pem \
  --client-key=data/keys/kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
mv kube-scheduler.kubeconfig data/config
