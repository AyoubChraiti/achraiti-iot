#!/usr/bin/env bash
set -e

kubectl config use-context k3d-mycluster
kubectl apply -f "../gitlab.yaml"
kubectl -n gitlab rollout status statefulset/gitlab --timeout=1800s
