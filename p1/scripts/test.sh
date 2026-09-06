#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant validate

# One SSH session per machine checks the OS, resources, network and K3s service.
for vm in achraitiS achraitiSW; do
  if [[ $vm == achraitiS ]]; then
    ip=192.168.56.110 peer=192.168.56.111 service=k3s
  else
    ip=192.168.56.111 peer=192.168.56.110 service=k3s-agent
  fi
  vagrant ssh "$vm" -c "bash -s -- $vm $ip $peer $service" <<'REMOTE'
set -euo pipefail
trap 'echo "FAIL: check at line $LINENO on $(hostname)" >&2' ERR
. /etc/os-release
test "$ID" = debian && test "$VERSION_ID" = 13
test "$(hostname)" = "$1"
test "$(nproc)" = 1
awk '/MemTotal/ {exit !($2 >= 850000 && $2 <= 1200000)}' /proc/meminfo
ip -4 -o address show | grep -q " $2/"
ping -c 2 -W 2 "$3" >/dev/null
command -v k3s kubectl
systemctl is-active --quiet "$4"
systemctl is-enabled --quiet "$4"
echo "PASS: $1 — Debian 13, SSH, 1 CPU, 1 GiB, $2, $4"
REMOTE
done

# The server's kubectl must see exactly one controller and one worker.
vagrant ssh achraitiS -c 'bash -s' <<'REMOTE'
set -euo pipefail
trap 'echo "FAIL: cluster check at line $LINENO" >&2' ERR
kubectl wait --for=condition=Ready node/achraitis node/achraitisw --timeout=180s
test "$(kubectl get nodes --no-headers | wc -l)" = 2
test "$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | awk '{print $1}')" = achraitis
test "$(kubectl get node achraitis -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')" = 192.168.56.110
test "$(kubectl get node achraitisw -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')" = 192.168.56.111
kubectl -n kube-system wait --for=condition=Ready pods --all --timeout=180s
kubectl get nodes -o wide
REMOTE
echo 'All P1 checks passed.'
