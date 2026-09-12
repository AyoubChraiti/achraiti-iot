#!/bin/bash
set -euo pipefail
curl -sfL https://get.k3s.io | K3S_TOKEN="iotp1sharedtoken" sh -s - server \
  --node-ip=192.168.56.110 \
  --bind-address=192.168.56.110 \
  --flannel-iface=eth1 \
  --write-kubeconfig-mode=644
