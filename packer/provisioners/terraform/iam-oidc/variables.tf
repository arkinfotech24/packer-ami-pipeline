variable "region" {
  description = "AWS region for the OIDC setup"
  type        = string
  default     = "us-east-1"
}

variable "repo" {
  description = "GitHub repo for OIDC trust (e.g., org/repo)"
  type        = string
  default     = "arkinfotech24/packer-ami-pipeline"
}

