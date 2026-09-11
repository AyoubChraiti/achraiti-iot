#!/bin/bash

set -e

apt-get update -y
apt-get install -y curl

curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip 192.168.56.110 \
  --disable metrics-server \
  --disable local-storage

echo "=== Waiting for K3s ==="
until sudo kubectl get nodes >/dev/null 2>&1; do
    sleep 2
done

echo "=== K3s is ready ==="

sudo kubectl apply -f /vagrant/configs/deployments/

sudo kubectl apply -f /vagrant/configs/services/

sudo kubectl apply -f /vagrant/configs/ingress/