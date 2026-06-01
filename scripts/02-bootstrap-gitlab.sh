#!/usr/bin/env bash
# Bootstraps GitLab over SSH:
#  - reads the auto-generated initial root password
#  - sets a known root password
#  - creates a Personal Access Token via gitlab-rails
#  - writes ../.secrets/gitlab.env with URL, password, token
set -euo pipefail
cd "$(dirname "$0")/../terraform"

GITLAB_IP=$(terraform output -raw gitlab_public_ip)
SSH_KEY=$(terraform output -raw ssh_key_path)
GITLAB_URL=$(terraform output -raw gitlab_url)

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY")

NEW_PW="Zr9$(openssl rand -hex 8)Qx!"
TOKEN_VALUE="glpat-demo-$(openssl rand -hex 12)"

echo ">> Reading initial root password from GitLab"
ssh "${SSH_OPTS[@]}" ubuntu@"$GITLAB_IP" "sudo head -3 /etc/gitlab/initial_root_password 2>/dev/null || echo 'initial_root_password file not present (already rotated or removed)'" || true

echo ">> Building remote ruby script"
RUBY_SCRIPT=$(cat <<RUBY
u = User.find_by_username('root')
u.password = ENV['NEW_PW']
u.password_confirmation = ENV['NEW_PW']
u.password_automatically_set = false
u.skip_reconfirmation!
u.save!
puts "root password updated"

# Drop any prior demo tokens
u.personal_access_tokens.where(name: 'demo-bootstrap').find_each(&:revoke!)

t = u.personal_access_tokens.create!(
  scopes: ['api', 'read_repository', 'write_repository'],
  name: 'demo-bootstrap',
  expires_at: 30.days.from_now
)
t.set_token(ENV['TOKEN_VALUE'])
t.save!
puts "PAT saved"
RUBY
)

echo ">> Pushing root password reset + PAT creation to GitLab"
# Send the script as stdin into 'gitlab-rails runner -'
ssh "${SSH_OPTS[@]}" ubuntu@"$GITLAB_IP" \
  "sudo -E env NEW_PW='$NEW_PW' TOKEN_VALUE='$TOKEN_VALUE' gitlab-rails runner -" <<<"$RUBY_SCRIPT"

mkdir -p ../.secrets
cat > ../.secrets/gitlab.env <<EOF
GITLAB_URL=$GITLAB_URL
GITLAB_ROOT_PASSWORD=$NEW_PW
GITLAB_API_TOKEN=$TOKEN_VALUE
EOF
chmod 600 ../.secrets/gitlab.env

echo ">> Wrote ../.secrets/gitlab.env"
echo "URL:      $GITLAB_URL"
echo "User:     root"
echo "Password: $NEW_PW"
echo "Token:    $TOKEN_VALUE"

echo ">> Verifying token via API"
curl -sk --fail --header "PRIVATE-TOKEN: $TOKEN_VALUE" "$GITLAB_URL/api/v4/user" | jq '{username, id, is_admin}'
