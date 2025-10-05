terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -------------------------------
# Dynamic AMI selection based on OS + Env
# -------------------------------
data "aws_ami" "selected" {
  most_recent = true
  owners      = ["self"] # Limit to AMIs built in your account

  # Match Packer tags
  filter {
    name   = "tag:Project"
    values = ["packer-ami-pipeline"]
  }

  filter {
    name   = "tag:Environment"
    values = [var.env]
  }

  filter {
    name   = "tag:Distro"
    values = [var.distro]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# -------------------------------
# Launch Template using the selected AMI
# -------------------------------
resource "aws_launch_template" "this" {
  name_prefix   = "lt-${var.distro}-${var.env}-"
  image_id      = data.aws_ami.selected.id
  instance_type = "t3.micro"

  tag_specifications {
    resource_type = "instance"
    tags = {
      "Environment" = var.env
      "Distro"      = var.distro
      "CreatedBy"   = "Terraform"
    }
  }
}

# -------------------------------
# Outputs for visibility
# -------------------------------
output "selected_ami_id" {
  description = "The latest AMI ID dynamically selected based on Distro and Env"
  value       = data.aws_ami.selected.id
}

output "launch_template_id" {
  description = "Launch Template ID created with selected AMI"
  value       = aws_launch_template.this.id
}

