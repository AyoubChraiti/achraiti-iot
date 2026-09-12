#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

kubectl config use-context k3d-mycluster
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$SCRIPT_DIR/../gitlab.yaml"
kubectl -n gitlab rollout status statefulset/gitlab --timeout=1800s
