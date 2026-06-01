data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Pick one default subnet (first one)
locals {
  subnet_id = sort(data.aws_subnets.default.ids)[0]
}

resource "aws_security_group" "gitlab" {
  name        = "${var.name_prefix}-gitlab"
  description = "GitLab Omnibus"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP (admin IP only)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  ingress {
    description = "HTTPS (admin IP only)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  ingress {
    description = "Git SSH (admin IP only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  # The runner reaches GitLab over the public EIP, so egress leaves the
  # VPC and returns via the internet gateway — the source GitLab sees is the
  # runner's PUBLIC IP, not its security group. A SG-referenced rule would not
  # match that traffic, so we allow the runner's public IP explicitly.
  ingress {
    description = "HTTP from the runner (CI clone/push)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.runner.public_ip}/32"]
  }

  ingress {
    description = "Git SSH from the runner"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.runner.public_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-gitlab-sg" }
}

resource "aws_security_group" "runner" {
  name        = "${var.name_prefix}-runner"
  description = "GitLab Runner"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (admin)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-runner-sg" }
}
