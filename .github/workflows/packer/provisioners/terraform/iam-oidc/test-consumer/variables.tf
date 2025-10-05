variable "region" {
  description = "AWS region to deploy to"
  type        = string
}

variable "env" {
  description = "Environment (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "distro" {
  description = "Distro type (al2023, rhel9, ubuntu)"
  type        = string
  default     = "al2023"
}

variable "lt_name" {
  type    = string
  default = "lt-from-packer"
}

