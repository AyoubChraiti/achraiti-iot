#!/usr/bin/env bash

set -euo pipefail

readonly CLUSTER_NAME="mycluster"

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_MANIFEST="${SCRIPT_DIR}/../argocd.yaml"
readonly ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

[[ -f "$APP_MANIFEST" ]] || {
    echo "Missing Argo CD application manifest: $APP_MANIFEST" >&2
    exit 1
}

sudo -v

sudo apt-get update
sudo apt-get install -y ca-certificates curl

# Install Docker
if ! command -v docker >/dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
fi

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

# Install kubectl
if ! command -v kubectl >/dev/null; then
    curl -fsSLo /tmp/kubectl \
        "https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl"

    sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
fi

# Install k3d
if ! command -v k3d >/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# Reload Docker group permissions by restarting this script once
if ! docker info >/dev/null 2>&1; then
    exec sg docker -c "$0"
fi

# Create or start cluster
if k3d cluster list --no-headers | awk '{print $1}' | grep -Fxq "$CLUSTER_NAME"; then
    k3d cluster start "$CLUSTER_NAME" --wait
else
    k3d cluster create "$CLUSTER_NAME" --wait
fi

# configuring kubectl to use the newly created k3d clusted as the default context
kubectl config use-context "k3d-${CLUSTER_NAME}"

# Create namespaces
# i create namespaces this way instead of just "kubectl create namespace " so i don't get the error namespace already exists when the script is executed multiple times
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install Argo CD
kubectl apply -n argocd \
    --server-side \
    --force-conflicts \
    -f "$ARGOCD_INSTALL_URL"

kubectl wait \
    --for=condition=Established \
    crd/applications.argoproj.io \
    --timeout=120s

# Create Argo CD Application
kubectl apply -f "$APP_MANIFEST"