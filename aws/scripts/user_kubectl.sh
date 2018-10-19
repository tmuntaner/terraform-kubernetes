kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=tmp/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
    --client-certificate=tmp/admin.pem \
    --client-key=tmp/admin-key.pem \
    --kubeconfig=admin.kubeconfig

kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

kubectl config use-context kubernetes-the-hard-way --kubeconfig=admin.kubeconfig
