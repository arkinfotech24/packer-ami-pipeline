This document provides a comprehensive guide and full write-up, including an introduction to the workflows, for building **Hardened Amazon Machine Images (AMIs)** using **Packer**, **GitHub Actions**, and **Terraform**. This pipeline automates the AMI creation process, ensuring security compliance and seamless integration into a modern CI/CD environment.

I've created the comprehensive, multi-OS workflow with the detailed visual diagram, integrating **AWS**, **Packer**, **GitHub Actions**, and **Terraform** for a complete DevOps/SRE pipeline.

-----

# 🎨 Automated Hardened Multi-OS AMI Pipeline

This workflow automates the creation of hardened Amazon Machine Images (AMIs) for **Amazon Linux 2023 (AL2023)**, **Ubuntu**, and **RHEL 9** using a matrix strategy within **GitHub Actions**. It ensures secure, standardized, and repeatable image builds for multiple environments.

## Visual Workflow Diagram: Packer $\to$ Multi-OS AMI Build Pipeline 🌟

graph TD
    %% Define Subgraphs for Clear Separation and Coloring (Optional: GitHub renders colors based on node/subgraph definitions)
    subgraph S1 [GitHub Repository]
        direction TD
        A[Developer Commits Code] --> B{Push/PR to main/develop};
    end
    
    subgraph S2 [GitHub Actions CI/CD Orchestration]
        direction LR
        B --> C(1. Workflow Triggered);
        C --> D{2. OIDC Authentication};
        D --> E(3. Assume AWS IAM Role);
        E --> F[4. Matrix Strategy Start];
    end

    subgraph S3 [Parallel Packer Builds in AWS]
        direction LR
        G1{Job: AL2023 Build}
        G2{Job: Ubuntu Build}
        G3{Job: RHEL 9 Build}
        
        F --> G1;
        F --> G2;
        F --> G3;

        G1 --> H1(Packer Build: AL2023 Provisioners);
        G2 --> H2(Packer Build: Ubuntu Provisioners);
        G3 --> H3(Packer Build: RHEL 9 Provisioners);
        
        H1 --> I1[AL2023 AMI Created & Tagged];
        H2 --> I2[Ubuntu AMI Created & Tagged];
        H3 --> I3[RHEL 9 AMI Created & Tagged];
    end
    
    subgraph S4 [Deployment and Artifact Tracking]
        direction TD
        J(5. Collect 3 AMI IDs & Upload Manifests to S3);
        K{6. Terraform Deployment Job};
        L[Terraform Apply \n(Consumes all 3 new AMIs)];
        M[Hardened AMIs Ready for Use];
    end
    
    %% Connect Parallel Outputs to Sequential Next Step
    I1 & I2 & I3 --> J;
    
    J --> K;
    K --> L;
    L --> M;
    
    %% Style adjustments for better visualization (GitHub-specific styling is limited, but this makes the flow clear)
    style S1 fill:#E6FFED,stroke:#238636,stroke-width:2px
    style S2 fill:#F0F8FF,stroke:#007BFF,stroke-width:2px
    style S3 fill:#FFF5E6,stroke:#FF9900,stroke-width:2px
    style S4 fill:#E8E8FF,stroke:#6F42C1,stroke-width:2px


The diagram illustrates the flow from code commit to the final, deployable AMIs, showing the interaction between the cloud provider, CI/CD tool, and infrastructure-as-code tools.

-----

## 1\. AWS and Terraform Infrastructure Setup

This foundational step ensures secure access for the CI/CD pipeline.

**Location:** `terraform/iam-oidc/main.tf`

```terraform
# IAM OIDC Provider: Trusts GitHub's identity token
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["<YOUR_PROVIDER_THUMBPRINT>"] 
}

# IAM Role: Assumed by GitHub Actions Runner (Builds)
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
            "token.actions.githubusercontent.com:sub" : "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:ref:refs/heads/*" 
          }
        }
      },
    ]
  })
}

# IAM Policy: Grants permissions for Packer to create and manage EC2 resources
resource "aws_iam_role_policy_attachment" "packer_access" {
  role       = aws_iam_role.packer_github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess" # Use managed policy for brevity; prefer scoped custom policy
}

# IAM Policy: Grants permission to pass the EC2 Instance Profile role
resource "aws_iam_role_policy" "packer_pass_role" {
  role = aws_iam_role.packer_github_actions_role.id
  name = "PackerPassRolePolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

-----

## 2\. Packer Configuration (Multi-OS Dynamic Build)

The Packer files are set up to dynamically adjust based on the `os_name` variable passed from the GitHub Actions matrix.

### File: `packer/variables.pkr.hcl` (Key Definitions)

```hcl
variable "os_name" {
  type    = string
  default = "al2023"
  validation {
    condition = contains(["al2023", "ubuntu", "rhel9"], var.os_name)
    error_message = "The 'os_name' variable must be one of 'al2023', 'ubuntu', or 'rhel9'."
  }
}

locals {
  os_details = {
    al2023 = {
      source_ami_name_filter = "al2023-ami-minimal-*"
      ssh_username           = "ec2-user"
      ami_owners             = ["amazon"]
      provisioners           = ["00-base.sh", "10-hardening-al2023.sh", "20-cloudwatch-agent.sh"]
    }
    ubuntu = {
      source_ami_name_filter = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      ssh_username           = "ubuntu"
      ami_owners             = ["099720109477"]
      provisioners           = ["00-base.sh", "10-hardening-ubuntu.sh", "20-cloudwatch-agent.sh"]
    }
    rhel9 = {
      source_ami_name_filter = "RHEL-9*-x86_64-*-Hourly2-EBS"
      ssh_username           = "ec2-user"
      ami_owners             = ["309956199498"] # Red Hat owner ID
      provisioners           = ["00-base.sh", "10-hardening-rhel9.sh", "20-cloudwatch-agent.sh"]
    }
  }
}
// ... other variables ...
```

### File: `packer/ami-pkr.hcl` (Build Logic)

```hcl
source "amazon-ebs" "base" {
  // ... static configurations ...
  
  // Dynamic Source Selection
  source_ami_filter {
    filters = {
      name                = local.os_details[var.os_name].source_ami_name_filter
    }
    owners      = local.os_details[var.os_name].ami_owners
    most_recent = true
  }
  
  ssh_username                = local.os_details[var.os_name].ssh_username
  ami_name                    = "hardened-${var.os_name}-${var.environment}-AMI-{{timestamp}}"
  
  // ... tags, instance_profile_name ...
}

build {
  name    = "hardened-image-build-${var.os_name}"
  sources = ["source.amazon-ebs.base"]

  // Dynamic Provisioner Execution based on OS
  dynamic "provisioner" {
    for_each = local.os_details[var.os_name].provisioners
    content {
      type            = "shell"
      scripts         = ["provisioners/${provisioner.value}"]
      execute_command = "sudo {{.Path}}"
      # Ensure hardening scripts (e.g., 10-hardening-*.sh) use `set -e` to fail on error
    }
  }

  // Post-Processor: Manifest output
  post-processor "manifest" {
    output = "manifest-${var.os_name}.json" // Unique manifest file per OS
    strip_private_properties = true
  }
}
```

-----

## 3\. GitHub Actions Workflow (CI/CD Orchestration)

The workflow uses a matrix to parallelize the AMI builds for the three operating systems.

**File:** `.github/workflows/packer-build.yml`

```yaml
name: Automated Packer AMI Pipeline - Multi-OS Build

on:
  push:
    branches: [ main, develop ]
    paths: [ 'packer/**' ]
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

env:
  IAM_ROLE_ARN: arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/packer-github-actions-role # Masked Secret
  AWS_REGION: us-east-1
  PACKER_TEMPLATE: packer/ami-pkr.hcl

jobs:
  build_ami:
    runs-on: ubuntu-latest
    
    # 🌟 Matrix Strategy to build all three OSs in parallel 🌟
    strategy:
      fail-fast: false
      matrix:
        os_type: [ al2023, ubuntu, rhel9 ] # Targets the three OSs
    
    # Define outputs to be consumed by the deployment job
    outputs:
      al2023_ami_id: ${{ steps.build_output.outputs.al2023_ami_id }}
      ubuntu_ami_id: ${{ steps.build_output.outputs.ubuntu_ami_id }}
      rhel9_ami_id: ${{ steps.build_output.outputs.rhel9_ami_id }}

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Configure AWS Credentials with OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.IAM_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Packer
        uses: hashicorp/setup-packer@main
        with:
          version: "latest" 

      - name: Determine Environment Variables
        id: vars
        run: |
          ENV_NAME="${{ github.ref_name == 'main' && 'prod' || 'dev' }}"
          echo "ENV_VARS_FILE=packer/vars/${ENV_NAME}.pkrvars.hcl" >> $GITHUB_OUTPUT
          echo "PACKER_ENV_VAR=${ENV_NAME}" >> $GITHUB_OUTPUT
          
      - name: Validate and Build AMI for ${{ matrix.os_type }}
        id: build
        run: |
          packer validate \
            -var-file=${{ steps.vars.outputs.ENV_VARS_FILE }} \
            -var "os_name=${{ matrix.os_type }}" \
            ${{ env.PACKER_TEMPLATE }}
            
          packer build \
            -var-file=${{ steps.vars.outputs.ENV_VARS_FILE }} \
            -var "os_name=${{ matrix.os_type }}" \
            ${{ env.PACKER_TEMPLATE }}
        env:
          GITHUB_SHA: ${{ github.sha }}

      - name: Extract AMI ID and Set Job Output
        id: build_output
        run: |
          # The manifest name is dynamic: manifest-{os_name}.json
          MANIFEST_FILE="manifest-${{ matrix.os_type }}.json"
          AMI_ID=$(jq -r '.builds[0].artifact_id' ${MANIFEST_FILE} | cut -d ':' -f 2)
          
          # Sets the AMI ID as a unique output variable for the deployment job
          echo "::set-output name=${{ matrix.os_type }}_ami_id::${AMI_ID}" 
          echo "Built AMI ID: ${AMI_ID} for ${{ matrix.os_type }}"
          
          # Optional: Upload artifact (manifest)
          # aws s3 cp ${MANIFEST_FILE} s3://your-build-manifests/${{ matrix.os_type }}/${{ github.sha }}/manifest.json
          
  deploy_test_consumer:
    needs: build_ami
    runs-on: ubuntu-latest
    # Only run if all builds in the matrix succeeded
    if: success()
    environment: prod # Target environment for deployment
    
    steps:
      - name: Configure AWS Credentials (for deployment)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.IAM_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Deploy Test Consumers with New AMIs
        run: |
          cd terraform/test-consumer
          terraform init
          
          # Pass all three AMI IDs from the matrix output to Terraform
          terraform apply -auto-approve \
            -var "al2023_ami_id=${{ needs.build_ami.outputs.al2023_ami_id }}" \
            -var "ubuntu_ami_id=${{ needs.build_ami.outputs.ubuntu_ami_id }}" \
            -var "rhel9_ami_id=${{ needs.build_ami.outputs.rhel9_ami_id }}"
```
