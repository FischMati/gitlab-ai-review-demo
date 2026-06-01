output "gitlab_url" {
  value = local.gitlab_external_url
}

output "gitlab_public_ip" {
  value = aws_eip.gitlab.public_ip
}

output "gitlab_instance_id" {
  value = aws_instance.gitlab.id
}

output "runner_instance_id" {
  value = aws_instance.runner.id
}

output "runner_public_ip" {
  value = aws_instance.runner.public_ip
}

output "ssh_key_path" {
  value = local_sensitive_file.private_key.filename
}

output "ssh_gitlab" {
  value = "ssh -i ${local_sensitive_file.private_key.filename} ubuntu@${aws_eip.gitlab.public_ip}"
}

output "ssh_runner" {
  value = "ssh -i ${local_sensitive_file.private_key.filename} ubuntu@${aws_instance.runner.public_ip}"
}
