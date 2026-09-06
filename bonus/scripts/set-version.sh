#!/bin/bash
# Make a real commit in local GitLab; Argo CD performs the Kubernetes update.
set -euo pipefail
VERSION=${1:-}
[[ $VERSION == v1 || $VERSION == v2 ]] || { echo 'Usage: set-version.sh v1|v2' >&2; exit 1; }
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SECRETS_DIR=$SCRIPT_DIR/../.secrets
[[ -s $SECRETS_DIR/curl.conf ]] || { echo 'Run bonus/scripts/setup.sh first.' >&2; exit 1; }
API=http://127.0.0.1:8081/api/v4/projects/root%2Fachraiti-iot
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
curl --config "$SECRETS_DIR/curl.conf" -fsS --max-time 30 \
  "$API/repository/files/p3%2Fconfs%2Fdeployment.yaml/raw?ref=main" > "$TEMP_DIR/deployment.yaml"
if grep -q "image: wil42/playground:$VERSION" "$TEMP_DIR/deployment.yaml"; then
  echo "GitLab already specifies $VERSION."
else
  sed -i "s|image: wil42/playground:v[12]|image: wil42/playground:$VERSION|" "$TEMP_DIR/deployment.yaml"
  jq -n --rawfile content "$TEMP_DIR/deployment.yaml" --arg version "$VERSION" \
    '{branch:"main",content:$content,commit_message:("Use playground " + $version)}' > "$TEMP_DIR/update.json"
  curl --config "$SECRETS_DIR/curl.conf" -fsS --max-time 120 --request PUT \
    --header 'Content-Type: application/json' --data-binary "@$TEMP_DIR/update.json" \
    "$API/repository/files/p3%2Fconfs%2Fdeployment.yaml" >/dev/null
fi
bash "$SCRIPT_DIR/test.sh" "$VERSION"
