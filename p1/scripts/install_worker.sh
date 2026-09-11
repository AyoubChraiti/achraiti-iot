#!/bin/sh
set -eu
WORKER_IP=192.168.56.111
: "${K3S_TOKEN:?K3S_TOKEN is required}"
apt-get update
apt-get install -y curl ca-certificates
swapoff -a
IFACE=$(ip -o -4 addr show | awk -v ip="$WORKER_IP/" 'index($4, ip) == 1 {print $2}')
: "${IFACE:?Cannot find the private network interface}"
timeout 180 sh -c 'until curl -fksS --connect-timeout 2 --max-time 5 https://192.168.56.110:6443/ping >/dev/null; do sleep 2; done'
curl -fsSL --retry 3 https://get.k3s.io -o /tmp/install-k3s.sh
K3S_URL=https://192.168.56.110:6443 \
INSTALL_K3S_EXEC="agent --node-ip=$WORKER_IP --flannel-iface=$IFACE --node-name=achraitisw" \
  sh /tmp/install-k3s.sh
systemctl is-active --quiet k3s-agent
