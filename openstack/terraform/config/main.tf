resource "null_resource" "generate_config" {
  provisioner "local-exec" {
    command = <<CMD
rm -f tmp/*.pem tmp/*.csr tmp/*.json tmp/*.kubeconfig admin.kubeconfig
cd tmp
../../scripts/certs.sh
../../scripts/server_kubectl.sh
../../scripts/configs.sh
cd ..
./../scripts/user_kubectl.sh
CMD

    environment {
      KUBERNETES_INTERNAL_ADDRESS = "${var.internal_dns_name}"
      KUBERNETES_PUBLIC_ADDRESS   = "${var.public_dns_name}"
    }
  }
}
