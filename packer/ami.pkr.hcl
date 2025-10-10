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
  type = string
}

variable "version" {
  type = string
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
# Locals
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
# Source Blocks
# -----------------------------
source "amazon-ebs" "al2023" {
  region               = var.region
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  security_group_id    = var.security_group_id
  iam_instance_profile = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username         = "ec2-user"
  ami_name             = local.ami_names.al2023
  ami_description      = "Hardened Amazon Linux 2023 AMI (${var.env}) version ${var.version}"
  ami_virtualization_type = "hvm"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags          = merge(local.base_tags, { "BuildName" = "build-al2023" })
  snapshot_tags = local.base_tags
}

source "amazon-ebs" "rhel9" {
  region               = var.region
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  security_group_id    = var.security_group_id
  iam_instance_profile = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username         = "ec2-user"
  ami_name             = local.ami_names.rhel9
  ami_description      = "Hardened RHEL 9 AMI (${var.env}) version ${var.version}"
  ami_virtualization_type = "hvm"

  source_ami_filter {
    filters = {
      name                = "RHEL-9.*x86_64*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["309956199498"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags          = merge(local.base_tags, { "BuildName" = "build-rhel9" })
  snapshot_tags = local.base_tags
}

source "amazon-ebs" "ubuntu" {
  region               = var.region
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  security_group_id    = var.security_group_id
  iam_instance_profile = var.iam_instance_profile != "" ? var.iam_instance_profile : null
  ssh_username         = "ubuntu"
  ami_name             = local.ami_names.ubuntu
  ami_description      = "Hardened Ubuntu LTS AMI (${var.env}) version ${var.version}"
  ami_virtualization_type = "hvm"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags          = merge(local.base_tags, { "BuildName" = "build-ubuntu" })
  snapshot_tags = local.base_tags
}

# -----------------------------
# Build Blocks
# -----------------------------
# -----------------------------
# Build Blocks
# -----------------------------
build {
  name    = "build-al2023"
  sources = ["source.amazon-ebs.al2023"]

  provisioner "shell" {
    script            = "${path.root}/provisioners/00-base.sh"
    execute_command   = "sudo -E bash '{{.Path}}'"
    environment_vars  = ["ENVIRONMENT=${var.env}", "DISTRO=al2023"]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  provisioner "shell" {
    script            = "${path.root}/provisioners/10-hardening-al2023.sh"
    execute_command   = "sudo -E bash '{{.Path}}'"
    environment_vars  = ["ENVIRONMENT=${var.env}", "DISTRO=al2023"]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  provisioner "shell" {
    script            = "${path.root}/provisioners/20-cloudwatch-agent.sh"
    execute_command   = "sudo -E bash '{{.Path}}'"
    pause_before      = "5s"
    environment_vars  = ["ENVIRONMENT=${var.env}", "DISTRO=al2023"]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  provisioner "shell" {
    inline = ["echo ✅ Build complete: al2023-${var.env}-${var.version}"]
  }

  post-processor "manifest" {
    output = "${path.root}/manifest-al2023.json"
  }
}

build {
  name    = "build-rhel9"
  sources = ["source.amazon-ebs.rhel9"]

  provisioner "shell" {
    script            = "${path.root}/provisioners/00-base.sh"
    execute_command   = "sudo -E bash '{{.Path}}'"
    environment_vars  = ["ENVIRONMENT=${var.env}", "DISTRO=rhel9"]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  provisioner "shell" {
    script            = "${path.root}/provisioners/10-hardening-rhel9.sh"
    execute_command   = "sudo -E bash '{{.Path}}'"
    environment_vars  = ["ENVIRONMENT=${var.env}", "DISTRO=rhel9"]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  provisioner "shell" {
    script            = "${path.root}/provisioners/20-cloudwatch-agent.sh"
    execute_command   = "sudo -E bash '{{.Path}}'"
    pause_before      = "5s"
    environment_vars  = ["ENVIRONMENT=${var.env}", "DISTRO=rhel9"]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  provisioner "shell" {
    inline = ["echo ✅ Build complete: rhel9-${var.env}-${var.version}"]
  }

  post-processor "manifest" {
    output = "${path.root}/manifest-rhel9.json"
  }
}

build {
  name    = "build-ubuntu"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    script            = "${path.root}/provisioners/00-base.sh"
    execute_command   = "sudo -E bash '{{.Path}}'"
    environment_vars  = ["ENVIRONMENT=${var.env}", "DISTRO=ubuntu"]
    expect_disconnect = true
    valid_exit_codes  = [0, 1, 2300218]
  }

  provisioner "shell" {
    inline = ["echo ✅ Build complete: ubuntu-${var.env}-${var.version}"]
  }

  post-processor "manifest" {
    output = "${path.root}/manifest-ubuntu.json"
  }
}
