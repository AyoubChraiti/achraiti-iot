#!/bin/sh

set -eu

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"
WORKER_NODE="achraitisw"

: "${K3S_TOKEN:?K3S_TOKEN is required}"

echo "[worker] Installing dependencies..."

apt-get update
apt-get install -y curl ca-certificates

echo "[worker] Waiting for the server..."

until curl -ks --connect-timeout 2 \
  "https://${SERVER_IP}:6443/ping" >/dev/null
do
  sleep 2
done

echo "[worker] Installing K3s agent..."

curl -sfL https://get.k3s.io |
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="agent \
    --node-ip=${WORKER_IP} \
    --node-name=${WORKER_NODE}" \
  sh -

echo "[worker] Ready."