#!/bin/bash

RANCHER_HOST=$1

if [[ -z "$RANCHER_HOST" ]]; then
    echo "ERROR: Missing 'RANCHER_HOST' environment variable."
    exit 1
fi

echo ""
echo "====================================="
echo "1) Installing RKE2.."
echo "====================================="
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server
systemctl start rke2-server

echo ""
echo "====================================="
echo "2) Waiting for cluster to be ready.."
echo "====================================="
until KUBECONFIG=/etc/rancher/rke2/rke2.yaml /var/lib/rancher/rke2/bin/kubectl cluster-info; do
  sleep 3
done

echo ""
echo "====================================="
echo "3) Installing cert-manager (v1.7.1).."
echo "====================================="
helm install --namespace cert-manager --create-namespace --set installCRDs=true cert-manager /charts/cert-manager-v1.7.1.tgz

echo ""
echo "======================================="
echo "5) Creating 'cattle-system' namespace.."
echo "======================================="
kubectl create namespace cattle-system

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

helm install --namespace cattle-system -f /tmp/rancher-values.yaml rancher /charts/rancher-2.6.8.tgz
