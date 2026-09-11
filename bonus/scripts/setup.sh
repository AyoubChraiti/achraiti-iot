#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SECRETS_DIR=$SCRIPT_DIR/../.secrets
k() { kubectl --context k3d-iot-cluster "$@"; }
k -n argocd get application wil-playground >/dev/null
umask 077
mkdir -p "$SECRETS_DIR"
k create namespace gitlab --dry-run=client -o yaml | k apply -f -
if ! k -n gitlab get secret gitlab-root-password >/dev/null 2>&1; then
  if [[ ! -s $SECRETS_DIR/root-password ]]; then
    head -c 36 /dev/urandom | base64 > "$SECRETS_DIR/root-password"
  fi
  k -n gitlab create secret generic gitlab-root-password --from-file="password=$SECRETS_DIR/root-password"
fi
k -n gitlab get secret gitlab-root-password -o jsonpath='{.data.password}' | base64 -d > "$SECRETS_DIR/root-password"
k apply -f "$SCRIPT_DIR/../confs/gitlab.yaml"
k -n gitlab rollout status statefulset/gitlab --timeout=1800s
curl -fsS --max-time 10 http://127.0.0.1:8081/users/sign_in >/dev/null
echo 'GitLab: http://localhost:8081 — username root'
echo "Initial password: $SECRETS_DIR/root-password (or the gitlab-root-password Kubernetes Secret)."
echo 'Next: create the public project, push the manifests, and connect Argo CD (bonus/README.md).'
