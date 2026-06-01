resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "demo" {
  key_name   = "${var.name_prefix}-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.demo.private_key_pem
  filename        = abspath("${path.module}/../.secrets/${var.name_prefix}.pem")
  file_permission = "0600"
}
