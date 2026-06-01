#!/usr/bin/env bash
# Creates a GitLab project, pushes the seed repo, sets CI variables.
set -euo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"
. "$HERE/.secrets/gitlab.env"

PROJECT_NAME="${PROJECT_NAME:-terraform-platform}"
PROJECT_PATH="${PROJECT_PATH:-terraform-platform}"

KIRO_API_KEY=$(cat "$HERE/.secrets/kiro_api_key" | tr -d '[:space:]')

echo ">> Creating project '$PROJECT_NAME' under root"
PROJECT_JSON=$(curl -sk --fail \
  --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
  --data "name=$PROJECT_NAME&path=$PROJECT_PATH&visibility=internal&initialize_with_readme=false" \
  "$GITLAB_URL/api/v4/projects")

PROJECT_ID=$(echo "$PROJECT_JSON" | jq -r '.id')
PROJECT_HTTP=$(echo "$PROJECT_JSON" | jq -r '.http_url_to_repo')
PROJECT_SSH=$(echo "$PROJECT_JSON"  | jq -r '.ssh_url_to_repo')
echo "   id=$PROJECT_ID  http=$PROJECT_HTTP"

# Embed token in URL for HTTPS push
AUTH_URL="${PROJECT_HTTP/http:\/\//http://oauth2:$GITLAB_API_TOKEN@}"

echo ">> Pushing seed-repo as 'main'"
SEED="$HERE/seed-repo"
WORK=$(mktemp -d)
cp -R "$SEED/." "$WORK/"
cd "$WORK"
git init -q -b main
git config user.email "demo@example.com"
git config user.name "Demo Bootstrap"
git add .
git commit -q -m "chore: initial Terraform platform"
git remote add origin "$AUTH_URL"
git push -q -u origin main
cd - >/dev/null
rm -rf "$WORK"

echo ">> Setting CI/CD variables (KIRO_API_KEY masked, GITLAB_API_TOKEN masked)"
set_var() {
  local key="$1" val="$2" masked="${3:-true}"
  curl -sk --fail \
    --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
    --data-urlencode "key=$key" \
    --data-urlencode "value=$val" \
    --data "masked=$masked&protected=false&variable_type=env_var" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables" \
    >/dev/null
  echo "   set $key (masked=$masked)"
}
set_var KIRO_API_KEY "$KIRO_API_KEY" true
set_var GITLAB_API_TOKEN "$GITLAB_API_TOKEN" true

cat >> "$HERE/.secrets/gitlab.env" <<EOF
PROJECT_ID=$PROJECT_ID
PROJECT_PATH=$PROJECT_PATH
PROJECT_HTTP_URL=$PROJECT_HTTP
EOF
echo ">> Done. Project URL: ${GITLAB_URL}/root/${PROJECT_PATH}"
