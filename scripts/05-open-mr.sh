#!/usr/bin/env bash
# Pushes a feature branch with a "bad" Terraform change and opens a Merge Request
# targeting main, which triggers the AI review pipeline.
set -euo pipefail
HERE="$(cd "$(dirname "$0")"/.. && pwd)"
. "$HERE/.secrets/gitlab.env"

WORK=$(mktemp -d)
AUTH_URL="${PROJECT_HTTP_URL/http:\/\//http://oauth2:$GITLAB_API_TOKEN@}"

git clone -q "$AUTH_URL" "$WORK"
cd "$WORK"
git config user.email "demo@example.com"
git config user.name "Demo Engineer"

BRANCH="feat/expose-redis"
git checkout -q -b "$BRANCH"

# Add a new resource that contains several issues for Kiro to find:
#   - Public Redis (Elasticache) with no auth token, no in-transit encryption
#   - Hardcoded secret string in user data
#   - Wide-open SG with port 6379
cat >> terraform/network.tf <<'HCL'

resource "aws_security_group" "redis" {
  name        = "demo-redis-sg"
  description = "Redis cache"

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
HCL

cat > terraform/cache.tf <<'HCL'
resource "aws_elasticache_cluster" "session" {
  cluster_id           = "demo-session-cache"
  engine               = "redis"
  node_type            = "cache.m5.large"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  security_group_ids   = [aws_security_group.redis.id]

  apply_immediately = true
}
HCL

git add terraform/
git commit -q -m "feat: add session redis cache"
git push -q -u origin "$BRANCH"

echo ">> Opening Merge Request"
MR_JSON=$(curl -sk --fail \
  --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
  --data "source_branch=$BRANCH&target_branch=main&title=feat: add session redis cache&remove_source_branch=true" \
  "$GITLAB_URL/api/v4/projects/$PROJECT_ID/merge_requests")

MR_IID=$(echo "$MR_JSON" | jq -r '.iid')
MR_URL=$(echo "$MR_JSON" | jq -r '.web_url')
echo "MR opened: $MR_URL  (iid=$MR_IID)"

cd - >/dev/null
rm -rf "$WORK"
echo "Watch the pipeline at: $GITLAB_URL/root/$PROJECT_PATH/-/merge_requests/$MR_IID/pipelines"
