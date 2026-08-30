#!/bin/sh

set -u

SERVER_VM="achraitiS"
WORKER_VM="achraitiSW"

SERVER_NODE="achraitis"
WORKER_NODE="achraitisw"

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"

FAILURES=0

cd "$(dirname "$0")" || exit 1

pass() {
  printf '[PASS] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

check() {
  description=$1
  shift

  if "$@" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

remote() {
  vm=$1
  command=$2

  vagrant ssh "$vm" -c "$command"
}

running() {
  vm=$1

  vagrant status "$vm" --machine-readable 2>/dev/null |
    awk -F, '
      $3 == "state" && $4 == "running" {
        found = 1
      }

      END {
        exit !found
      }
    '
}

wait_for_nodes() {
  attempt=0

  while [ "$attempt" -lt 90 ]
  do
    if remote "$SERVER_VM" \
      "test \"\$(kubectl get nodes --no-headers | wc -l)\" -eq 2 &&
       kubectl get nodes --no-headers |
       awk '\$2 != \"Ready\" { bad=1 } END { exit bad }'"
    then
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  return 1
}

wait_for_pods() {
  attempt=0

  while [ "$attempt" -lt 90 ]
  do
    if remote "$SERVER_VM" \
      "kubectl get pods --all-namespaces --no-headers |
       awk '
         {
           count++
         }

         \$4 != \"Running\" && \$4 != \"Completed\" {
           bad=1
         }

         END {
           exit count == 0 || bad
         }
       '"
    then
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  return 1
}

echo
echo "P1 validation"
echo "============="
echo

check "Vagrant is installed" command -v vagrant
check "Vagrantfile is valid" vagrant validate

check "$SERVER_VM is running" running "$SERVER_VM"
check "$WORKER_VM is running" running "$WORKER_VM"

check "SSH works on $SERVER_VM" \
  remote "$SERVER_VM" "true"

check "SSH works on $WORKER_VM" \
  remote "$WORKER_VM" "true"

check "$SERVER_VM hostname is correct" \
  remote "$SERVER_VM" \
  "test \"\$(hostname)\" = \"$SERVER_VM\""

check "$WORKER_VM hostname is correct" \
  remote "$WORKER_VM" \
  "test \"\$(hostname)\" = \"$WORKER_VM\""

check "$SERVER_VM has 1 CPU" \
  remote "$SERVER_VM" \
  "test \"\$(nproc)\" -eq 1"

check "$WORKER_VM has 1 CPU" \
  remote "$WORKER_VM" \
  "test \"\$(nproc)\" -eq 1"

check "$SERVER_VM has approximately 1024 MB RAM" \
  remote "$SERVER_VM" \
  "awk '/MemTotal/ {
     exit !(\$2 >= 850000 && \$2 <= 1200000)
   }' /proc/meminfo"

check "$WORKER_VM has approximately 1024 MB RAM" \
  remote "$WORKER_VM" \
  "awk '/MemTotal/ {
     exit !(\$2 >= 850000 && \$2 <= 1200000)
   }' /proc/meminfo"

check "$SERVER_VM owns $SERVER_IP" \
  remote "$SERVER_VM" \
  "ip -4 -o address show | grep -q ' $SERVER_IP/'"

check "$WORKER_VM owns $WORKER_IP" \
  remote "$WORKER_VM" \
  "ip -4 -o address show | grep -q ' $WORKER_IP/'"

check "$SERVER_VM can reach $WORKER_IP" \
  remote "$SERVER_VM" \
  "ping -c 2 -W 2 $WORKER_IP"

check "$WORKER_VM can reach $SERVER_IP" \
  remote "$WORKER_VM" \
  "ping -c 2 -W 2 $SERVER_IP"

check "K3s is installed on $SERVER_VM" \
  remote "$SERVER_VM" \
  "command -v k3s"

check "K3s is installed on $WORKER_VM" \
  remote "$WORKER_VM" \
  "command -v k3s"

check "kubectl is installed on $SERVER_VM" \
  remote "$SERVER_VM" \
  "command -v kubectl"

check "kubectl is installed on $WORKER_VM" \
  remote "$WORKER_VM" \
  "command -v kubectl"

check "K3s server service is active" \
  remote "$SERVER_VM" \
  "sudo systemctl is-active --quiet k3s"

check "K3s server service is enabled" \
  remote "$SERVER_VM" \
  "sudo systemctl is-enabled --quiet k3s"

check "K3s agent service is active" \
  remote "$WORKER_VM" \
  "sudo systemctl is-active --quiet k3s-agent"

check "K3s agent service is enabled" \
  remote "$WORKER_VM" \
  "sudo systemctl is-enabled --quiet k3s-agent"

check "Kubernetes API is listening on port 6443" \
  remote "$SERVER_VM" \
  "sudo ss -lnt | grep -q ':6443'"

check "kubectl works without sudo on $SERVER_VM" \
  remote "$SERVER_VM" \
  "kubectl get nodes"

check "Both Kubernetes nodes become Ready" \
  wait_for_nodes

check "$SERVER_NODE is Ready with IP $SERVER_IP" \
  remote "$SERVER_VM" \
  "kubectl get nodes -o wide --no-headers |
   awk '
     \$1 == \"$SERVER_NODE\" &&
     \$2 == \"Ready\" &&
     \$6 == \"$SERVER_IP\" {
       found=1
     }

     END {
       exit !found
     }
   '"

check "$WORKER_NODE is Ready with IP $WORKER_IP" \
  remote "$SERVER_VM" \
  "kubectl get nodes -o wide --no-headers |
   awk '
     \$1 == \"$WORKER_NODE\" &&
     \$2 == \"Ready\" &&
     \$6 == \"$WORKER_IP\" {
       found=1
     }

     END {
       exit !found
     }
   '"

check "$SERVER_NODE is the controller" \
  remote "$SERVER_VM" \
  "kubectl get node \"$SERVER_NODE\" --show-labels --no-headers |
   grep -q 'node-role.kubernetes.io/control-plane'"

check "The cluster contains exactly 2 nodes" \
  remote "$SERVER_VM" \
  "test \"\$(kubectl get nodes --no-headers | wc -l)\" -eq 2"

check "Kubernetes system pods become healthy" \
  wait_for_pods

echo

if [ "$FAILURES" -eq 0 ]; then
  echo "All P1 checks passed."
  echo
  vagrant ssh "$SERVER_VM" \
    -c "kubectl get nodes -o wide" 2>/dev/null
  exit 0
fi

echo "$FAILURES P1 check(s) failed."
echo
echo "Current cluster state:"

vagrant ssh "$SERVER_VM" \
  -c "kubectl get nodes -o wide" 2>/dev/null || true

exit 1
