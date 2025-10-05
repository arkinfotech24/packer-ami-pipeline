#########################################
# Terraform: AMI Consumer / Launch Template (Guaranteed Safe Fallback)
#########################################

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

#########################################
# Pull outputs from parent iam-oidc state
#########################################

data "terraform_remote_state" "oidc" {
  backend = "local"
  config = {
    path = "${path.module}/../terraform.tfstate"
  }
}

#########################################
# Define Fallback AMIs (VALID IDs YOU PROVIDED)
#########################################

locals {
  fallback_amis = {
    al2023 = "ami-0064d37a78289f7ec" # Amazon Linux 2023 (us-east-1)
    rhel9  = "ami-01b9ece719f53358e" # RHEL 9 official (us-east-1)
    ubuntu = "ami-00010cbd4af4db04e" # Ubuntu 24.04 LTS (us-east-1)
  }
}

#########################################
# Conditional AMI Lookup (Safe Wrapper)
#########################################

# Query for latest Packer-built AMI only if lookup_ami = true
data "aws_ami" "packer_ami" {
  count       = var.lookup_ami ? 1 : 0
  most_recent = true
  owners      = ["self"]

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

#########################################
# AMI Selection Logic (Safe Fallback)
#########################################

locals {
  # Only use AMI if lookup_ami=true and data query succeeded
  ami_from_data = (
    var.lookup_ami && length(data.aws_ami.packer_ami) > 0 ?
    try(data.aws_ami.packer_ami[0].id, null) :
    null
  )

  # Use fallback when no custom AMI exists
  selected_ami_id = coalesce(local.ami_from_data, local.fallback_amis[var.distro])

  # Track if fallback was used
  using_fallback = local.ami_from_data == null
}

#########################################
# Launch Template
#########################################

resource "aws_launch_template" "this" {
  name_prefix   = "lt-${var.distro}-${var.env}-"
  image_id      = local.selected_ami_id
  instance_type = "t3.micro"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Project       = "packer-ami-pipeline"
      Environment   = var.env
      Distro        = var.distro
      IAMRole       = data.terraform_remote_state.oidc.outputs.role_arn
      ManifestS3    = data.terraform_remote_state.oidc.outputs.s3_bucket
      InventoryDDB  = data.terraform_remote_state.oidc.outputs.dynamodb_table
      UsingFallback = tostring(local.using_fallback)
    }
  }
}

#########################################
# Outputs
#########################################

output "selected_ami_id" {
  description = "AMI ID used (Packer-built or fallback)"
  value       = local.selected_ami_id
}

output "using_fallback" {
  description = "True if fallback AMI was used"
  value       = local.using_fallback
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.this.id
}

output "from_iam_oidc_role_arn" {
  description = "IAM role ARN from iam-oidc module"
  value       = data.terraform_remote_state.oidc.outputs.role_arn
}

output "from_iam_oidc_s3_bucket" {
  description = "S3 bucket from iam-oidc module"
  value       = data.terraform_remote_state.oidc.outputs.s3_bucket
}

output "from_iam_oidc_dynamodb_table" {
  description = "DynamoDB table from iam-oidc module"
  value       = data.terraform_remote_state.oidc.outputs.dynamodb_table
}

