#!/usr/bin/env bash
# Tears down all AWS resources for this demo.
set -euo pipefail
cd "$(dirname "$0")/../terraform"
terraform destroy -auto-approve
echo ">> All demo infra destroyed."
