#!/bin/bash
set -euo pipefail

apt-get update -y
apt-get install -y curl

curl -sfL https://get.k3s.io \
  | K3S_URL=https://192.168.56.110:6443 K3S_TOKEN="iotp1sharedtoken" sh -s - agent \
    --node-ip=192.168.56.111 \
    --flannel-iface=eth1
