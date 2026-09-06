#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant validate
# Variables in the remote command must expand inside the guest.
# shellcheck disable=SC2016
vagrant ssh achraitiS -c '
  . /etc/os-release &&
  test "$ID" = debian && test "$VERSION_ID" = 13 &&
  test "$(hostname)" = achraitiS &&
  ip -4 -o addr show | grep -q " 192.168.56.110/" &&
  test "$(kubectl get nodes --no-headers | wc -l)" -eq 1 &&
  kubectl wait --for=condition=Ready node/achraitis --timeout=120s &&
  kubectl rollout status deployment/app1 --timeout=180s &&
  kubectl rollout status deployment/app2 --timeout=180s &&
  kubectl rollout status deployment/app3 --timeout=180s &&
  test "$(kubectl get deployment app2 -o jsonpath="{.status.readyReplicas}")" = 3 &&
  kubectl get ingress applications
'
for entry in app1.com:app1 app2.com:app2 unknown.example:app3 192.168.56.110:app3; do
  host=${entry%:*}
  app=${entry#*:}
  body=$(curl -fsS --retry 12 --retry-connrefused --retry-delay 5 --max-time 10 -H "Host: $host" http://192.168.56.110/)
  [[ "$body" == *"<h1>$app</h1>"* ]]
  echo "PASS: $host -> $app"
done
echo 'All P2 checks passed.'
