#!/usr/bin/env bash
# Provisions GitLab + Runner on AWS via Terraform.
set -euo pipefail
cd "$(dirname "$0")/../terraform"

terraform init -upgrade
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan
rm -f tfplan
terraform output
