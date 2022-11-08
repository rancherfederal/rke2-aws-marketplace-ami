#!/bin/bash

RANCHER_HOST=$1
RANCHER_BOOTSTRAP_PASSWORD=$2

echo ""
echo "====================================="
echo "1) Creating symlink for kubectl.."
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
until KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl get daemonset -n kube-system rke2-ingress-nginx-controller > /dev/null 2>&1; do
    sleep 3
done
  
echo "Waiting for pods to be ready.."
until [[ $(KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl get ds -n kube-system rke2-ingress-nginx-controller -o json | jq -r '.status.numberReady') == $(KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl get ds -n kube-system rke2-ingress-nginx-controller -o json | jq -r '.status.desiredNumberScheduled') ]]; do
    sleep 3
done

if [[ $(KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm status -n cert-manager cert-manager -o json 2>/dev/null | jq -r '.info.status') != "deployed" ]]; then
  echo ""
  echo "====================================="
  echo "3) Installing cert-manager (v1.7.1).."
  echo "====================================="
  KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm install --wait --namespace cert-manager --create-namespace --set installCRDs=true cert-manager /charts/cert-manager-v1.7.1.tgz

  # Wait for cert-manager pods to ensure Rancher can install issuer
  kubectl wait --for=condition=Ready pods --all -n cert-manager
fi

if [[ $(KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm status -n kube-system aws-cloud-controller-manager -o json 2>/dev/null | jq -r '.info.status') != "deployed" ]]; then
  # echo ""
  # echo "====================================="
  # echo "3) Configuring AWS Cloud Provider.."
  # echo "====================================="
  # KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm install --namespace kube-system --create-namespace aws-cloud-controller-manager /charts/aws-cloud-controller-manager-0.0.7.tgz

  echo ""
  echo "======================================================="
  echo "4) Updating native NGINX chart to type 'LoadBalancer'.."
  echo "======================================================="
  mv /charts/rke2-ingress-nginx-config.yaml /var/lib/rancher/rke2/server/manifests/rke2-ingress-nginx-config.yaml
fi

echo ""
echo "======================================="
echo "5) Creating 'cattle-system' namespace if it doesn't exist.."
echo "======================================="
cat <<EOF | KUBECONFIG=/etc/rancher/rke2/rke2.yaml kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: cattle-system
  labels:
    name: cattle-system
EOF

if [[ $(KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm status -n cattle-system rancher -o json 2>/dev/null | jq -r '.info.status') != "deployed" ]]; then
  echo ""
  echo "======================="
  echo "6) Installing Rancher.."
  echo "======================="
  cat <<EOT > /tmp/rancher-values.yaml
hostname: $RANCHER_HOST
replicas: 3
bootstrapPassword: $RANCHER_BOOTSTRAP_PASSWORD
EOT
  sleep 10
  KUBECONFIG=/etc/rancher/rke2/rke2.yaml helm install --namespace cattle-system -f /tmp/rancher-values.yaml rancher /charts/rancher-2.6.8.tgz
fi