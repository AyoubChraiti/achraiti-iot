#!/usr/bin/env bash

set -euo pipefail

echo "========================================"
echo " Installing k3d environment"
echo " Docker + kubectl + k3d"
echo "========================================"

# --------------------------------------------------
# 1. Check operating system
# --------------------------------------------------

if [ ! -f /etc/os-release ]; then
    echo "Error: Cannot determine Linux distribution."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    echo "Error: This script supports Ubuntu and Debian only."
    exit 1
fi

echo "[+] Detected OS: $PRETTY_NAME"


# --------------------------------------------------
# 2. Determine the real user
# --------------------------------------------------
# If the script is executed with sudo, $USER becomes root.
# SUDO_USER gives us the user who originally invoked sudo.

TARGET_USER="${SUDO_USER:-$USER}"

echo "[+] Target user: $TARGET_USER"


# --------------------------------------------------
# 3. Install basic dependencies
# --------------------------------------------------

echo "[+] Installing base dependencies..."

sudo apt-get update

sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg


# --------------------------------------------------
# 4. Install Docker
# --------------------------------------------------

echo "[+] Installing Docker..."

# Docker's official GPG key directory
sudo install -m 0755 -d /etc/apt/keyrings

# Select Docker repository depending on the distribution
if [ "$ID" = "ubuntu" ]; then
    DOCKER_URL="https://download.docker.com/linux/ubuntu"
    DOCKER_CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
else
    DOCKER_URL="https://download.docker.com/linux/debian"
    DOCKER_CODENAME="$VERSION_CODENAME"
fi

# Download Docker's signing key
sudo curl -fsSL \
    "$DOCKER_URL/gpg" \
    -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: $DOCKER_URL
Suites: $DOCKER_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update

# Install Docker Engine and related components
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin


# --------------------------------------------------
# 5. Start and enable Docker
# --------------------------------------------------

echo "[+] Starting Docker..."

sudo systemctl enable docker
sudo systemctl start docker


# --------------------------------------------------
# 6. Allow current user to use Docker without sudo
# --------------------------------------------------

echo "[+] Adding $TARGET_USER to docker group..."

sudo usermod -aG docker "$TARGET_USER"


# --------------------------------------------------
# 7. Verify Docker
# --------------------------------------------------

echo "[+] Verifying Docker installation..."

sudo docker version

echo "[+] Testing Docker..."

sudo docker run --rm hello-world


# --------------------------------------------------
# 8. Install kubectl
# --------------------------------------------------

echo "[+] Installing kubectl..."

# Determine CPU architecture
ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        KUBECTL_ARCH="amd64"
        ;;
    aarch64|arm64)
        KUBECTL_ARCH="arm64"
        ;;
    armv7l)
        KUBECTL_ARCH="arm"
        ;;
    *)
        echo "Unsupported CPU architecture: $ARCH"
        exit 1
        ;;
esac

# Get latest stable Kubernetes release
KUBECTL_VERSION="$(
    curl -L -s https://dl.k8s.io/release/stable.txt
)"

echo "[+] Installing kubectl $KUBECTL_VERSION..."

curl -LO \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl"

curl -LO \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl.sha256"

# Verify checksum
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

# Install binary
sudo install \
    -o root \
    -g root \
    -m 0755 \
    kubectl \
    /usr/local/bin/kubectl

rm -f kubectl kubectl.sha256


# --------------------------------------------------
# 9. Install k3d
# --------------------------------------------------

echo "[+] Installing k3d..."

curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash


# --------------------------------------------------
# 10. Verify installations
# --------------------------------------------------

echo
echo "========================================"
echo " Installation versions"
echo "========================================"

echo
echo "Docker:"
docker --version || sudo docker --version

echo
echo "kubectl:"
kubectl version --client

echo
echo "k3d:"
k3d version


# --------------------------------------------------
# Done
# --------------------------------------------------

echo
echo "========================================"
echo " Installation complete!"
echo "========================================"
echo
echo "IMPORTANT:"
echo
echo "Your user was added to the 'docker' group."
echo "You must log out and log back in for the"
echo "group change to fully take effect."
echo
echo "Alternatively, run:"
echo
echo "    newgrp docker"
echo
echo "Then test:"
echo
echo "    docker ps"
echo
echo "You can then create your k3d cluster with:"
echo
echo "    k3d cluster create mycluster"
echo
echo "And verify it with:"
echo
echo "    kubectl get nodes"
echo
