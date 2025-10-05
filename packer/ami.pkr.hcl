packer {
  required_version = ">= 1.11.0"
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
    }
  }
}

# -----------------------------
# Variables
# -----------------------------
variable "region" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "env" {
  type = string # dev/test/prod
}

variable "version" {
  type = string # injected from Git or manually
}

variable "distro" {
  type = string # "al2023" | "rhel9" | "ubuntu"
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "iam_instance_profile" {
  type    = string
  default = ""
}

variable "root_volume_size" {
  type    = number
  default = 16
}

variable "cwagent" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

# -----------------------------
# Local variables & tagging
# -----------------------------
locals {
  base_tags = merge({
    "Project"     = "packer-ami-pipeline",
    "Environment" = var.env,
    "Version"     = var.version,
    "BuiltBy"     = "GitHubActions"
  }, var.tags)

  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())

  ami_names = {
    al2023 = "hardened-al2023-${var.env}-${var.version}-${local.timestamp}"
    rhel9  = "hardened-rhel9-${var.env}-${var.version}-${local.timestamp}"
    ubuntu = "hardened-ubuntu-${var.env}-${var.version}-${local.timestamp}"
  }
}

# -----------------------------
# AMAZON LINUX 2023
# -----------------------------
source "amazon-ebs" "al2023" {
  region                   = var.region
  instance_type            = var.instance_type
  subnet_id                = var.subnet_id
  security_group_id        = var.security_group_id
  iam_instance_profile     = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username             = "ec2-user"
  ami_name                 = local.ami_names.al2023
  ami_description          = "Hardened Amazon Linux 2023 AMI (${var.env}) version ${var.version}"
  ami_virtualization_type  = "hvm"
  force_deregister         = false
  force_delete_snapshot    = false

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"] # Amazon
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags          = local.base_tags
  snapshot_tags = local.base_tags
}

# -----------------------------
# RHEL 9
# -----------------------------
source "amazon-ebs" "rhel9" {
  region                   = var.region
  instance_type            = var.instance_type
  subnet_id                = var.subnet_id
  security_group_id        = var.security_group_id
  iam_instance_profile     = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username             = "ec2-user"
  ami_name                 = local.ami_names.rhel9
  ami_description          = "Hardened RHEL 9 AMI (${var.env}) version ${var.version}"
  ami_virtualization_type  = "hvm"

  source_ami_filter {
    filters = {
      name                = "RHEL-9.*x86_64*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["309956199498"] # Red Hat official
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags          = local.base_tags
  snapshot_tags = local.base_tags
}

# -----------------------------
# Ubuntu 22.04 / 24.04 LTS
# -----------------------------
source "amazon-ebs" "ubuntu" {
  region                   = var.region
  instance_type            = var.instance_type
  subnet_id                = var.subnet_id
  security_group_id        = var.security_group_id
  iam_instance_profile     = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username             = "ubuntu"
  ami_name                 = local.ami_names.ubuntu
  ami_description          = "Hardened Ubuntu LTS AMI (${var.env}) version ${var.version}"
  ami_virtualization_type  = "hvm"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags          = local.base_tags
  snapshot_tags = local.base_tags
}

# -----------------------------
# Build Definition
# -----------------------------
build {
  sources = [
    "source.amazon-ebs.al2023",
    "source.amazon-ebs.rhel9",
    "source.amazon-ebs.ubuntu"
  ]

  # Base setup (package install, basic config)
  provisioner "shell" {
    script = "${path.root}/provisioners/00-base.sh"
    environment_vars = [
      "ENVIRONMENT=${var.env}",
      "DISTRO=${var.distro}"
    ]
  }

  # Security hardening
  provisioner "shell" {
    script = "${path.root}/provisioners/10-hardening.sh"
    environment_vars = [
      "ENVIRONMENT=${var.env}",
      "DISTRO=${var.distro}"
    ]
  }

  # CloudWatch Agent (optional)
  provisioner "shell" {
    only = [
      "amazon-ebs.al2023",
      "amazon-ebs.rhel9",
      "amazon-ebs.ubuntu"
    ]
    script = "${path.root}/provisioners/20-cloudwatch-agent.sh"
    pause_before = "5s"
    environment_vars = [
      "ENVIRONMENT=${var.env}",
      "DISTRO=${var.distro}"
    ]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  # Final log
  provisioner "shell" {
    inline = [
      "echo ✅ Build complete: ${var.distro}-${var.env}-${var.version}"
    ]
  }

  post-processor "manifest" {
    output = "${path.root}/manifest.json"
  }

   # Optional — uncomment to upload manifest to S3
   post-processor "shell-local" {
     inline = [
       "aws s3 cp ${path.root}/manifest.json s3://ami-manifests-arkinfotech24-packer-ami-pipeline-us-east-1/"
     ]
   }
}

