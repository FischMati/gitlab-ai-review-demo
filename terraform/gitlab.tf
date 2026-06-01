resource "aws_eip" "gitlab" {
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-gitlab-eip" }
}

locals {
  gitlab_external_url = "http://${aws_eip.gitlab.public_ip}"

  gitlab_user_data = <<-EOF
    #!/bin/bash
    exec > /var/log/user-data.log 2>&1
    set -eux

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl ca-certificates tzdata perl openssh-server postfix jq

    # Install GitLab CE
    curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
    EXTERNAL_URL="${local.gitlab_external_url}" apt-get install -y gitlab-ce

    # Mark ready
    touch /var/lib/cloud/gitlab-ready
  EOF
}

resource "aws_instance" "gitlab" {
  ami                    = var.ami_id
  instance_type          = var.gitlab_instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.gitlab.id]
  key_name               = aws_key_pair.demo.key_name
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data_replace_on_change = false
  user_data                   = local.gitlab_user_data

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = { Name = "${var.name_prefix}-gitlab" }
}

resource "aws_eip_association" "gitlab" {
  instance_id   = aws_instance.gitlab.id
  allocation_id = aws_eip.gitlab.id
}
