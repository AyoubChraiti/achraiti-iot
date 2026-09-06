#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFS_DIR=$SCRIPT_DIR/../confs
# shellcheck source=../confs/versions.env
source "$CONFS_DIR/versions.env"
for tool in docker k3d kubectl curl jq git; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Run sudo bash p3/scripts/install-tools.sh first." >&2; exit 1; }
done
docker info >/dev/null
REPO_URL=$(sed -n 's/^    repoURL: //p' "$CONFS_DIR/argocd-app.yaml")
if ! GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "$REPO_URL" refs/heads/main | grep -q refs/heads/main; then
  echo "Publish this project on the public repository $REPO_URL (main branch), then rerun." >&2
  exit 1
fi
if ! k3d cluster list -o json | jq -e '.[] | select(.name == "iot-cluster")' >/dev/null; then
  k3d cluster create iot-cluster \
    --image "rancher/k3s:${K3S_VERSION/+/-}" \
    --servers 1 --agents 0 \
    --port '127.0.0.1:8888:30888@server:0' \
    --port '127.0.0.1:8081:30081@server:0' \
    --k3s-arg '--disable=traefik,servicelb,metrics-server@server:0' \
    --wait --timeout 180s
else
  k3d cluster start iot-cluster
fi
k3d kubeconfig merge iot-cluster --kubeconfig-switch-context
k() { kubectl --context k3d-iot-cluster "$@"; }
k wait --for=condition=Ready nodes --all --timeout=180s
k apply -f "$CONFS_DIR/namespace.yaml"
k apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"
k -n argocd wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
k -n argocd rollout status deployment/argocd-server --timeout=600s
k -n argocd rollout status deployment/argocd-repo-server --timeout=600s
k -n argocd rollout status statefulset/argocd-application-controller --timeout=600s
k apply -f "$CONFS_DIR/argocd-app.yaml"
echo 'Argo CD login: admin (retrieve its password with the command in README.md).'
echo 'App: http://localhost:8888'
echo 'Dashboard: kubectl --context k3d-iot-cluster -n argocd port-forward svc/argocd-server 8080:443'
