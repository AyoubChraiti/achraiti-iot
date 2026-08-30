#!/bin/sh

set -eu

SERVER_IP="192.168.56.110"
PRIVATE_INTERFACE="eth1"
KUBECONFIG_GROUP="k3s-admin"

echo "[server] Installing dependencies..."

apt-get update
DEBIAN_FRONTEND=noninteractive \
    apt-get install -y curl ca-certificates

echo "[server] Configuring kubectl access..."

getent group "$KUBECONFIG_GROUP" >/dev/null 2>&1 ||
    groupadd --system "$KUBECONFIG_GROUP"

usermod -aG "$KUBECONFIG_GROUP" vagrant

echo "[server] Installing K3s..."

curl -sfL https://get.k3s.io |
    INSTALL_K3S_CHANNEL="stable" sh -s - server \
        --node-ip "$SERVER_IP" \
        --advertise-address "$SERVER_IP" \
        --tls-san "$SERVER_IP" \
        --flannel-iface "$PRIVATE_INTERFACE" \
        --write-kubeconfig-mode "0640" \
        --write-kubeconfig-group "$KUBECONFIG_GROUP"

echo "[server] Waiting for K3s..."

attempt=0

until k3s kubectl get nodes >/dev/null 2>&1; do
    attempt=$((attempt + 1))

    if [ "$attempt" -ge 30 ]; then
        echo "[server] K3s failed to become ready."
        journalctl -u k3s --no-pager -n 30
        exit 1
    fi

    sleep 2
done

echo "[server] K3s server is ready."
k3s kubectl get nodes -o wide