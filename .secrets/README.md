# .secrets/

This directory holds local credentials and generated artifacts. **Nothing here
is committed** except this README and the `*.example` templates (see the root
`.gitignore`).

## What you need to provide

- `kiro_api_key` — your Kiro API key (Pro/Pro+/Power). Copy from the template:
  ```bash
  cp .secrets/kiro_api_key.example .secrets/kiro_api_key
  # then edit it and paste your real key
  ```

## What gets generated automatically

- `gitlab.env` — written by `scripts/02-bootstrap-gitlab.sh` (GitLab URL, root
  password, API token) and appended by `scripts/03-create-project.sh`. See
  `gitlab.env.example` for the shape.
- `<name_prefix>.pem` — the SSH private key, created by Terraform
  (`keypair.tf`). Used by the helper scripts to SSH into the EC2 hosts.

Treat every real file in this folder as a secret. Do not share or commit them.
