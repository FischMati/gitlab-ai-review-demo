#!/usr/bin/env bash
# Registers the EC2 runner against the GitLab project using a fresh registration token.
set -euo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"
. "$HERE/.secrets/gitlab.env"
cd "$HERE/terraform"

RUNNER_IP=$(terraform output -raw runner_public_ip)
SSH_KEY=$(terraform output -raw ssh_key_path)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"

echo ">> Requesting project runner registration token"
REG_JSON=$(curl -sk --fail \
  --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
  --data "runner_type=project_type&project_id=$PROJECT_ID&description=demo-runner&tag_list=demo-runner&run_untagged=false&locked=false" \
  "$GITLAB_URL/api/v4/user/runners")
REG_TOKEN=$(echo "$REG_JSON" | jq -r '.token')
RUNNER_ID=$(echo "$REG_JSON" | jq -r '.id')
echo "   runner_id=$RUNNER_ID"

echo ">> Waiting for runner host bootstrap (gitlab-runner installed)"
for i in $(seq 1 60); do
  if ssh $SSH_OPTS ubuntu@$RUNNER_IP "test -f /var/lib/cloud/runner-ready" >/dev/null 2>&1; then
    echo "   ready"
    break
  fi
  printf "."
  sleep 10
done

echo ">> Registering runner on EC2 host"
ssh $SSH_OPTS ubuntu@$RUNNER_IP sudo gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL/" \
  --token "$REG_TOKEN" \
  --executor "shell" \
  --description "ec2-shell-runner"

echo ">> Verifying runner is online"
ssh $SSH_OPTS ubuntu@$RUNNER_IP sudo gitlab-runner list || true
ssh $SSH_OPTS ubuntu@$RUNNER_IP sudo gitlab-runner verify || true

echo "Runner registration done."
