#!/bin/bash

RANCHER_HOST=$1
RKE2_VERSION="v1.23.10+rke2r1"

if [[ -z "$RANCHER_HOST" ]]; then
    echo "ERROR: Missing 'RANCHER_HOST' environment variable."
    exit 1
fi

echo ""
echo "====================================="
echo "1) Installing RKE2.."
echo "====================================="
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=$RKE2_VERSION sh -
systemctl enable rke2-server
systemctl start rke2-server

echo ""
echo "====================================="
echo "2) Creating symlink for kubectl.."
echo "====================================="
while [ ! -f /var/lib/rancher/rke2/bin/kubectl ]
do
  sleep 2
done
ln -s /var/lib/rancher/rke2/bin/kubectl /usr/bin/kubectl

echo ""
echo "====================================="
echo "2) Waiting for cluster to be ready.."
echo "====================================="
echo "Waiting for DaemonSet to be created.."
until [[ $(KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl get pods --no-headers -n kube-system -l app.kubernetes.io/name=rke2-ingress-nginx | wc -l | awk '{ print $1 }') -gt 0 ]]; do
    sleep 3
done
echo "Waiting for pods to be ready.."
KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl wait pods -n kube-system -l app.kubernetes.io/name=rke2-ingress-nginx --for condition=Ready --timeout=300s

echo ""
echo "====================================="
echo "3) Installing cert-manager (v1.7.1).."
echo "====================================="
KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm install --namespace cert-manager --create-namespace --set installCRDs=true cert-manager /charts/cert-manager-v1.7.1.tgz

echo ""
echo "======================================="
echo "5) Creating 'cattle-system' namespace.."
echo "======================================="
KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl create namespace cattle-system

echo ""
echo "======================="
echo "7) Installing Rancher.."
echo "======================="
cat <<EOT > /tmp/rancher-values.yaml
hostname: $RANCHER_HOST

replicas: 1
ingress:
  extraAnnotations:
    kubernetes.io/ingress.class: nginx
EOT

KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm install --namespace cattle-system -f /tmp/rancher-values.yaml rancher /charts/rancher-2.6.8.tgz
