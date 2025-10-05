#########################################
# Variables for AMI Consumer / Launch Template
#########################################

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "env" {
  description = "Environment (dev/test/prod)"
  type        = string
  default     = "dev"
}

variable "distro" {
  description = "Linux distribution (al2023, rhel9, ubuntu)"
  type        = string
  default     = "al2023"
}

variable "lookup_ami" {
  description = "If false, skip AMI lookup entirely and use fallback public AMI"
  type        = bool
  default     = true
}

