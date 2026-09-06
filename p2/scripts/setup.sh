#!/bin/sh
set -eu
apt-get update
apt-get install -y curl ca-certificates
swapoff -a
IFACE=$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.56\.110\// {print $2}')
: "${IFACE:?Cannot find the private network interface}"
curl -fsSL --retry 3 https://get.k3s.io -o /tmp/install-k3s.sh
INSTALL_K3S_EXEC="server --node-ip=192.168.56.110 --advertise-address=192.168.56.110 --flannel-iface=$IFACE --node-name=achraitis --disable=metrics-server --write-kubeconfig-mode=644" \
  sh /tmp/install-k3s.sh

timeout 180 sh -c 'until kubectl get node achraitis >/dev/null 2>&1; do sleep 2; done'
kubectl wait --for=condition=Ready node/achraitis --timeout=180s
kubectl apply -f /vagrant/confs/
for app in app1 app2 app3; do
  kubectl rollout status "deployment/$app" --timeout=300s
done
timeout 300 sh -c 'until kubectl -n kube-system get deployment traefik >/dev/null 2>&1; do sleep 3; done'
kubectl -n kube-system rollout status deployment/traefik --timeout=300s
kubectl get deployments,services,ingresses
