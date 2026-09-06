#!/bin/bash
set -euo pipefail
EXPECTED=${1:-}
[[ -z $EXPECTED || $EXPECTED == v1 || $EXPECTED == v2 ]] || { echo 'Usage: test.sh [v1|v2]' >&2; exit 1; }
k() { kubectl --context k3d-iot-cluster "$@"; }
k get namespace argocd dev
k wait --for=condition=Ready nodes --all --timeout=180s
# Wait for a fully synchronized, healthy application at the expected version.
for ((attempt=0; attempt<120; attempt++)); do
  state=$(k -n argocd get application wil-playground -o json)
  if jq -e '
    .status.sync.status == "Synced" and .status.health.status == "Healthy" and
    .status.sync.comparedTo.source.repoURL == .spec.source.repoURL and
    .status.sync.comparedTo.source.path == .spec.source.path and
    .status.sync.comparedTo.source.targetRevision == .spec.source.targetRevision
  ' <<< "$state" >/dev/null; then
    body=$(curl -fsS --max-time 5 http://127.0.0.1:8888/ || true)
    if jq -e --arg version "$EXPECTED" '.status == "ok" and (.message == "v1" or .message == "v2") and ($version == "" or .message == $version)' <<< "$body" >/dev/null 2>&1; then
      actual=$(k -n dev get deployment wil-playground -o jsonpath='{.spec.template.spec.containers[0].image}')
      served=$(jq -r .message <<< "$body")
      if [[ $actual == "wil42/playground:$served" ]]; then
        k -n dev rollout status deployment/wil-playground --timeout=120s
        echo "PASS: Argo CD Synced/Healthy, $actual, HTTP $body"
        exit 0
      fi
    fi
  fi
  sleep 5
done
k -n argocd get application wil-playground -o yaml
k -n dev get pods -o wide
k -n dev get events --sort-by=.lastTimestamp
echo 'FAIL: GitOps deployment did not become healthy at the requested version.' >&2
exit 1
