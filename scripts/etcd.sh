cat > etcd-csr.json <<EOF
{
  "CN": "kube-etcd",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Nuremberg",
      "O": "Kubernetes",
      "OU": "kube-etcd",
      "ST": "Bayern"
    }
  ]
}
EOF

cfssl gencert \
  -ca=keys/ca.pem \
  -ca-key=keys/ca-key.pem \
  -config=ca-config.json \
  -hostname=10.240.8.10,10.240.16.10,10.240.24.10,127.0.0.1 \
  -profile=kubernetes \
  etcd-csr.json | cfssljson -bare etcd

rm etcd-csr.json etcd.csr
mv etcd.pem keys
mv etcd-key.pem keys
