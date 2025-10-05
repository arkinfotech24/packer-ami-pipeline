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
variable "region"              { type = string }
variable "instance_type"       { type = string, default = "t3.micro" }
variable "env"                 { type = string }                # dev/test/prod
variable "version"             { type = string }                # injected from Git
variable "distro"              { type = string }                # "al2023" | "rhel9" | "ubuntu"
variable "subnet_id"           { type = string }
variable "security_group_id"   { type = string }
variable "iam_instance_profile" { type = string, default = "" }
variable "root_volume_size"    { type = number, default = 16 }
variable "cwagent"             { type = bool, default = true }

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
    "Distro"      = var.distro,
    "BuiltBy"     = "GitHubActions"
  }, var.tags)

  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
  ami_name  = "hardened-${var.distro}-${var.env}-${var.version}-${local.timestamp}"
}

# -----------------------------
# Amazon Linux 2023
# -----------------------------
source "amazon-ebs" "al2023" {
  region                   = var.region
  instance_type            = var.instance_type
  subnet_id                = var.subnet_id
  security_group_id        = var.security_group_id
  iam_instance_profile     = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username             = "ec2-user"
  ami_name                 = local.ami_name
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
    device_name          = "/dev/xvda"
    volume_size          = var.root_volume_size
    volume_type          = "gp3"
    delete_on_termination = true
  }

  tags          = local.base_tags
  snapshot_tags = local.base_tags
}

# -----------------------------
# RHEL 9
# -----------------------------
source "amazon-ebs" "rhel9" {
  region                = var.region
  instance_type         = var.instance_type
  subnet_id             = var.subnet_id
  security_group_id     = var.security_group_id
  iam_instance_profile  = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username          = "ec2-user"
  ami_name              = local.ami_name
  ami_description       = "Hardened RHEL 9 AMI (${var.env}) version ${var.version}"
  ami_virtualization_type = "hvm"

  source_ami_filter {
    filters = {
      name                = "RHEL-9.*x86_64*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["309956199498"] # Red Hat
    most_recent = true
  }

  launch_block_device_mappings {
    device_name          = "/dev/xvda"
    volume_size          = var.root_volume_size
    volume_type          = "gp3"
    delete_on_termination = true
  }

  tags          = local.base_tags
  snapshot_tags = local.base_tags
}

# -----------------------------
# Ubuntu 22.04 LTS (Jammy)
# -----------------------------
source "amazon-ebs" "ubuntu" {
  region                = var.region
  instance_type         = var.instance_type
  subnet_id             = var.subnet_id
  security_group_id     = var.security_group_id
  iam_instance_profile  = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username          = "ubuntu"
  ami_name              = local.ami_name
  ami_description       = "Hardened Ubuntu 22.04 LTS AMI (${var.env}) version ${var.version}"
  ami_virtualization_type = "hvm"

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
    device_name          = "/dev/sda1"
    volume_size          = var.root_volume_size
    volume_type          = "gp3"
    delete_on_termination = true
  }

  tags          = local.base_tags
  snapshot_tags = local.base_tags
}

# -----------------------------
# Build definition
# -----------------------------
build {
  sources = [
    "source.amazon-ebs.al2023",
    "source.amazon-ebs.rhel9",
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
    script = "${path.root}/provisioners/00-base.sh"
    environment_vars = [
      "ENVIRONMENT=${var.env}",
      "DISTRO=${var.distro}"
    ]
  }

  provisioner "shell" {
    script = "${path.root}/provisioners/10-hardening.sh"
  }

  provisioner "shell" {
    when   = "always"
    inline = ["echo 'Build complete: ${local.ami_name}'"]
  }

  provisioner "shell" {
    only   = [
      "amazon-ebs.al2023",
      "amazon-ebs.rhel9",
      "amazon-ebs.ubuntu"
    ]
    script            = "${path.root}/provisioners/20-cloudwatch-agent.sh"
    pause_before      = "5s"
    expect_disconnect = false
    only_if           = var.cwagent
  }

  post-processor "manifest" {
    output = "${path.root}/manifest.json"
  }
}

