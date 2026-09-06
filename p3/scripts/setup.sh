#!/bin/bash

set -e

CLUSTER_NAME="iot-cluster"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFS_DIR="$(dirname "$SCRIPT_DIR")/confs"

# ==============================================================================
# STEP 1: Install dependencies
# ==============================================================================

echo "Installing dependencies..."

if ! command -v docker &> /dev/null; then
    apt-get update > /dev/null 2>&1
    apt-get install -y docker.io > /dev/null 2>&1
    systemctl start docker
    systemctl enable docker
fi

if ! command -v kubectl &> /dev/null; then
    curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
fi

if ! command -v k3d &> /dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash > /dev/null 2>&1
fi

echo "Dependencies installed."

# ==============================================================================
# STEP 2: Create K3d cluster
# ==============================================================================

echo "Setting up K3d cluster..."

if ! k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    k3d cluster create "$CLUSTER_NAME" \
        --servers 1 \
        --agents 0 \
        --port 8080:80@loadbalancer \
        --port 8443:443@loadbalancer \
        --wait > /dev/null 2>&1
fi

k3d kubeconfig merge "$CLUSTER_NAME" --switch-context > /dev/null 2>&1

echo "Cluster ready."

# ==============================================================================
# STEP 3: Create namespaces
# ==============================================================================

echo "Creating namespaces..."

for ns in argocd dev; do
    kubectl get namespace "$ns" &> /dev/null || kubectl create namespace "$ns" > /dev/null 2>&1
done

echo "Namespaces created."

# ==============================================================================
# STEP 4: Install Argo CD
# ==============================================================================

echo "Installing Argo CD..."

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml > /dev/null 2>&1

kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd > /dev/null 2>&1 || true

echo "Argo CD installed."

# ==============================================================================
# STEP 5: Deploy application
# ==============================================================================

echo "Deploying application..."

kubectl apply -f "$CONFS_DIR/deployment.yaml" > /dev/null 2>&1
kubectl apply -f "$CONFS_DIR/service.yaml" > /dev/null 2>&1

sleep 5
kubectl wait --for=condition=ready pod -l app=wil-playground -n dev --timeout=120s > /dev/null 2>&1 || true

echo "Application deployed."

# ==============================================================================
# STEP 6: Get credentials
# ==============================================================================

ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Not ready yet")

# ==============================================================================
# Output summary
# ==============================================================================

echo ""
echo "=========================================="
echo "Setup Complete"
echo "=========================================="
echo ""
echo "Cluster Status:"
echo "  Name:       $CLUSTER_NAME"
echo "  Nodes:      $(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
echo "  Namespaces: argocd, dev"
echo ""
echo "Argo CD:"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "Access the Application:"
echo "  kubectl port-forward -n dev svc/wil-playground 8888:8888 &"
echo "  curl http://localhost:8888/"
echo ""
echo "Access Argo CD Dashboard:"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443 &"
echo "  Open: https://localhost:8080"
echo ""
