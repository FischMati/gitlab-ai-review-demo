variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "ai-review-demo"
}

variable "gitlab_instance_type" {
  type    = string
  default = "t3.large"
}

variable "runner_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS amd64 AMI for the chosen region"
  type        = string
  default     = "ami-02fd066b86800f60c"
}

variable "owner" {
  description = "Value for the Owner default tag applied to all resources"
  type        = string
  default     = "demo"
}

variable "allowed_admin_cidr" {
  description = "CIDR allowed to reach GitLab over HTTP/HTTPS/SSH. Set this to your own admin/egress IP range (e.g. \"203.0.113.10/32\"). Do NOT use 0.0.0.0/0."
  type        = string
}
