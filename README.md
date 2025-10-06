This document provides a comprehensive guide and full write-up, including an introduction to the workflows, for building **Hardened Amazon Machine Images (AMIs)** using **Packer**, **GitHub Actions**, and **Terraform**. This pipeline automates the AMI creation process, ensuring security compliance and seamless integration into a modern CI/CD environment.

-----

# 🚀 Automated Hardened AMI Pipeline: Packer, GitHub Actions, and Terraform

## Introduction to the Workflows

The AMI pipeline described here integrates three core tools to achieve a secure, automated, and repeatable process for managing base operating system images:

1.  **Terraform (Infrastructure Setup):** Manages the foundational AWS infrastructure required for the CI/CD pipeline, primarily the **IAM Roles** and **OpenID Connect (OIDC) Provider**. This enables GitHub Actions to securely assume a temporary role without storing long-lived credentials in the repository.
2.  **Packer (Image Builder):** Defines the AMI blueprint using HCL. It sources a base OS (e.g., Amazon Linux), launches a temporary EC2 instance, runs the **security hardening scripts (provisioners)**, and converts the resulting machine into a secure, tagged AMI.
3.  **GitHub Actions (Orchestrator):** Acts as the Continuous Integration/Continuous Delivery (CI/CD) engine. It triggers the Packer build on every relevant code push, handles secure AWS authentication via OIDC, validates the Packer template, executes the build, and prepares the output for downstream consumption (e.g., by a Terraform deployment module).

### Workflow Diagram: Packer $\to$ Terraform Pipeline

The visual workflow illustrates the data and control flow, starting from a developer committing code and ending with a hardened, deployable AMI.

$$\text{1. Developer Pushes Code (Packer/Scripts) to GitHub}$$$$\downarrow$$$$\text{2. GitHub Actions (\texttt{packer-build.yml}) Triggered}$$$$\downarrow$$$$\text{3. GitHub Actions Assumes IAM Role via OIDC (Credential-less)}$$$$\downarrow$$$$\text{4. Action Executes Packer Build using Environment-specific Vars (\texttt{packer build -var-file=...})}$$$$\downarrow$$$$\text{5. Packer Launches EC2 Instance in AWS}$$$$\downarrow$$$$\text{6. Packer Runs Shell Provisioners (\texttt{10-hardening.sh} applies fixes)}$$$$\downarrow$$$$\text{7. Hardened AMI Created, Tagged (with \texttt{GITHUB\_SHA}), and Registered}$$$$\downarrow$$$$\text{8. Manifest Output (with AMI ID) Saved/Uploaded to S3 (Tracking)}$$$$\downarrow$$$$\text{9. Downstream Action (Optional): Terraform \texttt{test-consumer} Deploys AMI}$$$$

-----

## 📂 Project Structure and File Location

This structure separates concerns, making the project maintainable and scalable.

| Directory/File | Purpose | Location |
| :--- | :--- | :--- |
| **`.github/workflows`** | **CI/CD Orchestration.** Contains the GitHub Actions workflow definition. | `.github/workflows/packer-build.yml` |
| **`terraform/iam-oidc`** | **Prerequisites.** Terraform module for creating the **IAM Role** and **OIDC** provider. | `terraform/iam-oidc/main.tf` |
| **`packer`** | **AMI Blueprint.** Root directory for Packer configuration files. | `packer/ami-pkr.hcl`, `packer/variables.pkr.hcl` |
| **`packer/provisioners`** | **Hardening/Fixes.** Shell scripts executed *inside* the EC2 instance during build. | `packer/provisioners/10-hardening.sh` |
| **`packer/vars`** | **Parameterization.** Environment-specific variable files for Packer. | `packer/vars/prod.pkrvars.hcl` |
| **`test-consumer`** | **Consumption/Validation.** Example Terraform module to consume the latest AMI ID. | `test-consumer/main.tf` |
| **`.gitignore`, `README.md`** | Standard repository files. | Root directory |

-----

## 🛠️ Step-by-Step Implementation Guide

### Step 1: Terraform Setup (OIDC and IAM Role) 🔑

This essential step provisions the secure method for the GitHub Action runner to interact with your AWS account.

**File:** `terraform/iam-oidc/main.tf`

```terraform
# IAM OIDC Provider: Trusts GitHub as an identity source
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["<YOUR_PROVIDER_THUMBPRINT>"] # Replace with actual thumbprint
}

# IAM Role: Assumed by GitHub Actions Runner
resource "aws_iam_role" "packer_github_actions_role" {
  name = "packer-github-actions-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" : "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:ref:refs/heads/main" 
          }
        }
      },
    ]
  })
}

# IAM Policy Attachment: Granting Packer necessary EC2 and S3 permissions
resource "aws_iam_role_policy" "packer_permissions" {
  role = aws_iam_role.packer_github_actions_role.id
  name = "PackerPermissionsPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
            "ec2:RunInstances", "ec2:CreateImage", "ec2:CreateTags", "ec2:TerminateInstances", "ec2:DeregisterImage",
            # ... all necessary EC2 actions ...
            "s3:PutObject" # For manifest upload
        ],
        Resource = "*"
      },
      # Must include iam:PassRole for the EC2 instance profile
      {
        Effect = "Allow",
        Action = "iam:PassRole",
        Resource = "arn:aws:iam::YOUR_ACCOUNT_ID:role/packer-instance-profile-role" 
      }
    ]
  })
}

output "iam_role_arn" {
  value = aws_iam_role.packer_github_actions_role.arn
}
```

**Action:** Run `terraform init` and `terraform apply` within `terraform/iam-oidc/`.

### Step 2: Packer Template and Variables Definition 📝

The core AMI definition, parameterized by environment.

**File:** `packer/ami-pkr.hcl`

```hcl
// Sourcing the latest Amazon Linux 2 (example)
source "amazon-ebs" "base" {
  region                      = var.aws_region
  source_ami_filter {
    filters = {
      name                = var.source_ami_name_filter # e.g., "amzn2-ami-hvm-*"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }
  
  instance_type               = var.instance_type
  ssh_username                = var.ssh_username
  ami_name                    = "hardened-${var.environment}-AMI-{{timestamp}}"
  
  tags = {
    Name           = "Hardened-Base-Image-${var.environment}"
    Environment    = var.environment
    Version        = "{{env `GITHUB_SHA`}}" // Tag with Git Commit SHA
  }
  iam_instance_profile        = var.instance_profile_name 
}

// Build Definition
build {
  name    = "hardened-image-build"
  sources = ["source.amazon-ebs.base"]

  // Provisioner 1: Base setup
  provisioner "shell" {
    scripts = ["provisioners/00-base.sh"]
    execute_command = "sudo {{.Path}}"
  }

  // Provisioner 2: SECURITY HARDENING
  provisioner "shell" {
    scripts = ["provisioners/10-hardening.sh"]
    execute_command = "sudo {{.Path}}"
    on_error        = "abort" // CRITICAL: Stop build if hardening fails
  }
  
  // Provisioner 3: Install Monitoring Agent
  provisioner "shell" {
    scripts = ["provisioners/20-cloudwatch-agent.sh"]
    execute_command = "sudo {{.Path}}"
  }

  // Post-Processor: Create build artifact manifest
  post-processor "manifest" {
    output = "manifest.json"
    strip_private_properties = true
  }
}
```

**File:** `packer/vars/prod.pkrvars.hcl` (Example Environment Variables)

```hcl
aws_region                = "us-east-1"
environment               = "prod"
instance_type             = "t3.large"
source_ami_name_filter    = "amzn2-ami-hvm-*"
ssh_username              = "ec2-user"
instance_profile_name     = "packer-instance-profile-role"
```

### Step 3: Provisioner Scripts (Hardening) 🔒

The hardening script ensures the AMI meets security baselines (e.g., CIS or STIG).

**File:** `packer/provisioners/10-hardening.sh`

```bash
#!/bin/bash
# 10-hardening.sh: Apply CIS/STIG Security Fixes
set -euxo pipefail # Exit on any non-zero command status

echo "--- Starting Security Hardening ---"

# FIX 1: Ensure password hashing algorithm is SHA-512 (CIS 5.4.1.1)
authconfig --passalgo=sha512 --update

# FIX 2: Restrict root access to console only
sed -i '/^root/s/bash/sbin\/nologin/' /etc/passwd

# FIX 3: Disable unused services for a minimal footprint (CIS 2.2.1-2.2.14)
systemctl disable avahi-daemon cups dhcpd dovecot httpd named nfs-server rpcbind smb snmpd
systemctl mask avahi-daemon cups

# FIX 4: Audit configuration changes
# Example: Ensure all login failures are logged
echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su

echo "--- Hardening complete. ---"
```

### Step 4: GitHub Actions Workflow (CI/CD) ⚙️

This is the orchestrator, automating the entire build process.

**File:** `.github/workflows/packer-build.yml`

```yaml
name: Automated Packer AMI Pipeline

on:
  push:
    branches: [ main, develop ] # Triggers on push to main or develop
    paths: [ 'packer/**' ]
  workflow_dispatch: # Allows manual trigger

permissions:
  id-token: write  # Crucial for OIDC authentication
  contents: read

env:
  # Masked Secrets: Replace with the ARN output from Terraform Step 1
  IAM_ROLE_ARN: arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/packer-github-actions-role
  AWS_REGION: us-east-1
  PACKER_TEMPLATE: packer/ami-pkr.hcl

jobs:
  build_ami:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Configure AWS Credentials with OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.IAM_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Set up Packer
        uses: hashicorp/setup-packer@main
        with:
          version: "latest" 

      - name: Determine Environment Variables
        id: vars
        run: |
          # Use 'prod' variables for main branch, 'dev' otherwise
          ENV_NAME="dev"
          if [[ "${{ github.ref_name }}" == "main" ]]; then
            ENV_NAME="prod"
          fi
          echo "ENV_VARS_FILE=packer/vars/${ENV_NAME}.pkrvars.hcl" >> $GITHUB_OUTPUT
          echo "PACKER_ENV_VAR=${ENV_NAME}" >> $GITHUB_OUTPUT
          
      - name: Validate and Build AMI
        id: build
        run: |
          packer validate -var-file=${{ steps.vars.outputs.ENV_VARS_FILE }} ${{ env.PACKER_TEMPLATE }}
          packer build -var-file=${{ steps.vars.outputs.ENV_VARS_FILE }} ${{ env.PACKER_TEMPLATE }}
        env:
          GITHUB_SHA: ${{ github.sha }} # Passes SHA for AMI Tagging

      - name: Extract AMI ID and Upload Manifest
        run: |
          # Extract AMI ID from manifest.json for tracking
          AMI_ID=$(jq -r '.builds[0].artifact_id' manifest.json | cut -d ':' -f 2)
          echo "AMI\_ID=$AMI\_ID" >> $GITHUB_ENV
          echo "Successfully built AMI ID: $AMI\_ID for ${{ steps.vars.outputs.PACKER_ENV_VAR }}"
          
          # Upload manifest to S3 bucket for external tracking
          # aws s3 cp manifest.json s3://your-build-manifests/${{ steps.vars.outputs.PACKER_ENV_VAR }}/${{ github.sha }}/manifest.json

  deploy_test_consumer:
    needs: build_ami
    runs-on: ubuntu-latest
    environment: ${{ needs.build_ami.outputs.PACKER_ENV_VAR }}
    if: success() 
    steps:
      # ... (Steps to configure AWS credentials via OIDC - similar to above) ...
      - name: Deploy Test Consumer with New AMI
        uses: hashicorp/setup-terraform@v3
      - run: |
          cd terraform/test-consumer
          terraform init
          # Pass the output AMI ID from the build step to the deployment
          terraform apply -auto-approve -var "ami_id=${{ env.AMI_ID }}"
```
