#!/bin/sh

set -eu

SERVER_IP="192.168.56.110"
SERVER_NODE="achraitis"

: "${K3S_TOKEN:?K3S_TOKEN is required}"

echo "[server] Installing dependencies..."

apt-get update
apt-get install -y curl ca-certificates

echo "[server] Installing K3s..."

curl -sfL https://get.k3s.io |
  K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="server \
    --node-ip=${SERVER_IP} \
    --node-name=${SERVER_NODE} \
    --write-kubeconfig-mode=644" \
  sh -

echo "[server] Waiting for Kubernetes..."

until kubectl get node "$SERVER_NODE" >/dev/null 2>&1
do
  sleep 2
done

echo "[server] Ready."

kubectl get nodes -o wide