locals {
  runner_user_data = <<-EOF
    #!/bin/bash
    exec > /var/log/user-data.log 2>&1
    set -eux

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl ca-certificates jq git python3 python3-pip python3-requests unzip

    # GitLab Runner
    curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
    apt-get install -y gitlab-runner

    # Install Kiro CLI as the gitlab-runner user
    sudo -u gitlab-runner -H bash -lc 'curl -fsSL https://cli.kiro.dev/install | bash'

    # Ensure PATH for non-login shells used by gitlab-runner shell executor
    echo 'export PATH=$HOME/.local/bin:$PATH' | tee -a /home/gitlab-runner/.bashrc /home/gitlab-runner/.profile
    chown gitlab-runner:gitlab-runner /home/gitlab-runner/.bashrc /home/gitlab-runner/.profile

    touch /var/lib/cloud/runner-ready
  EOF
}

resource "aws_instance" "runner" {
  ami                    = var.ami_id
  instance_type          = var.runner_instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.runner.id]
  key_name               = aws_key_pair.demo.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data_replace_on_change = false
  user_data                   = local.runner_user_data

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = { Name = "${var.name_prefix}-runner" }
}
