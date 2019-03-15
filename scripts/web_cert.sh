#!/bin/bash

cat > cert.json <<EOF
{
  "CN": "kubernetes-dashboard.tmuntaner.scc.suse.de",
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
  -ca=data/keys/ca.pem \
  -ca-key=data/keys/ca-key.pem \
  -config=cfssl-config.json \
  -hostname=kubernetes-dashboard.tmuntaner.scc.suse.de \
  -profile=web \
  cert.json | cfssljson -bare kubernetes-dashboard.tmuntaner.scc.suse.de

rm cert.json kubernetes-dashboard.tmuntaner.scc.suse.de.csr
mv kubernetes-dashboard.tmuntaner.scc.suse.de.pem data/keys
mv kubernetes-dashboard.tmuntaner.scc.suse.de-key.pem data/keys
