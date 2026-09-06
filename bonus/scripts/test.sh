#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
k() { kubectl --context k3d-iot-cluster "$@"; }
k get namespace gitlab
k -n gitlab rollout status statefulset/gitlab --timeout=1800s
k -n gitlab get pvc storage-gitlab-0 -o json | jq -e '.status.phase == "Bound"' >/dev/null
source_url=$(k -n argocd get application wil-playground -o jsonpath='{.spec.source.repoURL}')
[[ $source_url == http://gitlab.gitlab.svc.cluster.local/root/achraiti-iot.git ]]
curl -fsS --max-time 10 http://127.0.0.1:8081/users/sign_in >/dev/null
bash "$SCRIPT_DIR/../../p3/scripts/test.sh" "$@"
echo 'PASS: local GitLab, persistent storage, and GitLab-driven Argo CD deployment.'
