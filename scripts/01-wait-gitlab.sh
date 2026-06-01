#!/usr/bin/env bash
# Waits until GitLab is reachable and ready.
set -euo pipefail
cd "$(dirname "$0")/../terraform"

URL=$(terraform output -raw gitlab_url)
echo "Waiting for GitLab at $URL ..."

for i in $(seq 1 90); do
  code=$(curl -sk -o /dev/null -w "%{http_code}" "$URL/users/sign_in" || true)
  if [ "$code" = "200" ] || [ "$code" = "302" ]; then
    echo "GitLab is up (HTTP $code) after ~$((i*10))s"
    exit 0
  fi
  printf "."
  sleep 10
done

echo "Timed out waiting for GitLab" >&2
exit 1
