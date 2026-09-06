#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
SECRETS_DIR=$ROOT_DIR/bonus/.secrets
k() { kubectl --context k3d-iot-cluster "$@"; }
k -n argocd get application wil-playground >/dev/null
# Create persistent credentials without putting them in Git or terminal output.
umask 077
mkdir -p "$SECRETS_DIR"
k create namespace gitlab --dry-run=client -o yaml | k apply -f -
if ! k -n gitlab get secret gitlab-root-password >/dev/null 2>&1; then
  if [[ ! -s $SECRETS_DIR/root-password ]]; then
    head -c 36 /dev/urandom | base64 > "$SECRETS_DIR/root-password"
  fi
  k -n gitlab create secret generic gitlab-root-password --from-file="password=$SECRETS_DIR/root-password"
fi
k -n gitlab get secret gitlab-root-password -o jsonpath='{.data.password}' | base64 -d > "$SECRETS_DIR/root-password"
k apply -f "$SCRIPT_DIR/../confs/gitlab.yaml"
# Restart on reruns too, so imagePullPolicy Always resolves the latest release.
k -n gitlab rollout restart statefulset/gitlab
k -n gitlab rollout status statefulset/gitlab --timeout=1800s
curl -fsS --retry 12 --retry-delay 5 --retry-connrefused --max-time 10 http://127.0.0.1:8081/users/sign_in >/dev/null
k -n gitlab exec -i gitlab-0 -- gitlab-rails runner - \
  < "$SCRIPT_DIR/create-token.rb" > "$SECRETS_DIR/api-token"
# Keep credentials out of curl's process arguments.
printf 'header = "PRIVATE-TOKEN: %s"\n' "$(tail -n 1 "$SECRETS_DIR/api-token")" > "$SECRETS_DIR/curl.conf"
api() { curl --config "$SECRETS_DIR/curl.conf" -fsS --max-time 120 "$@"; }
API=http://127.0.0.1:8081/api/v4
status=$(curl --config "$SECRETS_DIR/curl.conf" -sS -o "$SECRETS_DIR/project.json" -w '%{http_code}' "$API/projects/root%2Fachraiti-iot")
case $status in
  200) ;;
  404)
    api --request POST "$API/projects" \
      --data-urlencode 'name=achraiti-iot' --data-urlencode 'path=achraiti-iot' \
      --data-urlencode 'visibility=public' --data-urlencode 'initialize_with_readme=true' \
      --data-urlencode 'default_branch=main' > "$SECRETS_DIR/project.json"
    ;;
  *) echo "GitLab project lookup failed (HTTP $status)." >&2; exit 1 ;;
esac
PROJECT_ID=$(jq -er .id "$SECRETS_DIR/project.json")
jq -e '.visibility == "public"' "$SECRETS_DIR/project.json" >/dev/null || {
  echo 'The existing GitLab project must be public for anonymous Argo CD access.' >&2; exit 1;
}
# Seed only an uninitialized project; reruns must preserve a demonstrated v2.
status=$(curl --config "$SECRETS_DIR/curl.conf" -sS -o /dev/null -w '%{http_code}' "$API/projects/$PROJECT_ID/repository/files/p3%2Fconfs%2Fdeployment.yaml?ref=main")
case $status in
  200) echo 'Existing GitLab application manifests preserved.' ;;
  404)
    jq -n \
      --rawfile deployment "$ROOT_DIR/p3/confs/deployment.yaml" \
      --rawfile service "$ROOT_DIR/p3/confs/service.yaml" \
      --rawfile kustomization "$ROOT_DIR/p3/confs/kustomization.yaml" \
      '{branch:"main", commit_message:"Deploy playground through Argo CD", actions:[
        {action:"create",file_path:"p3/confs/deployment.yaml",content:$deployment},
        {action:"create",file_path:"p3/confs/service.yaml",content:$service},
        {action:"create",file_path:"p3/confs/kustomization.yaml",content:$kustomization}
      ]}' > "$SECRETS_DIR/commit.json"
    api --request POST --header 'Content-Type: application/json' \
      --data-binary "@$SECRETS_DIR/commit.json" "$API/projects/$PROJECT_ID/repository/commits" >/dev/null
    ;;
  *) echo "GitLab manifest lookup failed (HTTP $status)." >&2; exit 1 ;;
esac
# One controller owns the dev app; switch its source from GitHub to GitLab.
k apply -f "$SCRIPT_DIR/../confs/argocd-app.yaml"
k -n argocd annotate application wil-playground argocd.argoproj.io/refresh=hard --overwrite
bash "$SCRIPT_DIR/test.sh"
echo 'GitLab: http://localhost:8081 — username root'
echo "Initial password: $SECRETS_DIR/root-password (or the gitlab-root-password Kubernetes Secret)."
echo 'Demonstrate an update: bash bonus/scripts/set-version.sh v2'
