#!/bin/sh
set -eu
SERVER_IP=192.168.56.110
: "${K3S_TOKEN:?K3S_TOKEN is required}"
apt-get update
apt-get install -y curl ca-certificates
swapoff -a
IFACE=$(ip -o -4 addr show | awk -v ip="$SERVER_IP/" 'index($4, ip) == 1 {print $2}')
: "${IFACE:?Cannot find the private network interface}"
curl -fsSL --retry 3 https://get.k3s.io -o /tmp/install-k3s.sh
# The private interface carries both Kubernetes and pod-to-pod traffic.
INSTALL_K3S_EXEC="server --node-ip=$SERVER_IP --advertise-address=$SERVER_IP --flannel-iface=$IFACE --node-name=achraitis --disable=traefik,servicelb,metrics-server --write-kubeconfig-mode=644" \
  sh /tmp/install-k3s.sh
# Readable kubeconfig is a convenience for this disposable Vagrant lab.
timeout 180 sh -c 'until kubectl get node achraitis >/dev/null 2>&1; do sleep 2; done'
kubectl wait --for=condition=Ready node/achraitis --timeout=180s
kubectl get nodes -o wide
