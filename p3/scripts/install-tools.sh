#!/bin/bash
# Run once with sudo on the host VM; cluster setup runs as your normal user.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run: sudo bash $0" >&2; exit 1; }
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../confs/versions.env
source "$SCRIPT_DIR/../confs/versions.env"
case $(uname -m) in
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  *) echo 'Unsupported CPU architecture' >&2; exit 1 ;;
esac
apt-get update
apt-get install -y ca-certificates curl git jq docker.io rsync
systemctl enable --now docker
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
curl -fsSL --retry 3 "https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION/k3d-linux-$ARCH" -o "$TEMP_DIR/k3d-linux-$ARCH"
curl -fsSL --retry 3 "https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION/checksums.txt" -o "$TEMP_DIR/checksums.txt"
(cd "$TEMP_DIR"; awk -v file="k3d-linux-$ARCH" '$2 == file || $2 == "_dist/" file {print $1 "  " file}' checksums.txt | sha256sum --check)
install -m 0755 "$TEMP_DIR/k3d-linux-$ARCH" /usr/local/bin/k3d
# Match kubectl's minor version to the explicitly selected Kubernetes server.
KUBECTL_VERSION=${K3S_VERSION%%+*}
curl -fsSL --retry 3 "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl" -o "$TEMP_DIR/kubectl"
curl -fsSL --retry 3 "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl.sha256" -o "$TEMP_DIR/kubectl.sha256"
(cd "$TEMP_DIR"; printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum --check)
install -m 0755 "$TEMP_DIR/kubectl" /usr/local/bin/kubectl
if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
  usermod -aG docker "$SUDO_USER"
  if getent group libvirt >/dev/null; then usermod -aG libvirt "$SUDO_USER"; fi
  if getent group kvm >/dev/null; then usermod -aG kvm "$SUDO_USER"; fi
fi
echo 'Tools installed. Log out and back in to activate docker/libvirt group access.'
echo 'Then run: bash p3/scripts/setup.sh'
