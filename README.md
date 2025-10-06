🚀 packer-ami-pipeline
Production-grade AMI pipeline for secure, validated image builds across environments. Built with Packer, Terraform, Bash, and Ansible—modular, reproducible, and CI/CD-ready.

📦 `Repo Structure`
.
├── .github/workflows/           # CI/CD workflows (packer.yml, packer-build.yml)
├── packer/                      # Packer templates and HCL configs
├── provisioners/                # Bash scripts for layered provisioning
├── terraform/iam-oidc/          # Terraform IAM OIDC role setup
├── test-consumer/               # Consumer test harness for AMI validation
├── vars/                        # Environment-specific variable files
├── *.pkrvars.hcl                # dev/prod/test variable sets
├── *.pkr.hcl                    # Packer template entry points
├── *.tf                         # Terraform configs (main.tf, outputs.tf, variables.tf)
├── *.sh                         # Provisioning scripts (00-base.sh, 10-hardening.sh, etc.)
├── *.yml                        # CI/CD workflow definitions
├── manifest.json                # Packer build manifest
├── run-all.sh / build_all.sh    # Orchestration scripts
└── README.md

🧭 `Pipeline Flow`
graph TD
    A[CI/CD Trigger] --> B[Terraform IAM OIDC Setup]
    B --> C[Packer Init & Validate]
    C --> D[Packer Build AMI]
    D --> E[Provisioning Scripts]
    E --> F[Regression Test Kitchen]
    F --> G[Push Manifest & Metadata]
    G --> H[Test Consumer Harness]
    H --> I[Notify via GitHub Actions]

🔧 `Provisioning Layers`

Layer	Script	Purpose
00	00-base.sh	Base packages, system updates
10	10-hardening.sh	Security hardening, CIS benchmarks
20	20-cloudwatch-agent.sh	Monitoring agent install/config

🛠️ `Build Instructions`

1. `Initialize Packer`
bash
packer init packer/

2. `Validate Template`
bash
packer validate packer/ami.pkr.hcl

3. Build AMI `(e.g., dev)`
bash
packer build -var-file=vars/dev.pkrvars.hcl packer/ami.pkr.hcl

4. `Run All Provisioners`
bash run-all.sh

5. `Execute Regression Tests`
test-consumer/test.sh
🌐 Terraform IAM OIDC Setup
bash
cd terraform/iam-oidc
terraform init
terraform apply -var-file=vars/dev.tfvars
Creates IAM roles and OIDC trust for GitHub Actions to securely assume build permissions.

📬 `CI/CD Integration`
GitHub Actions workflows in .github/workflows/packer.yml and packer-build.yml automate:

Packer init/build

Terraform IAM provisioning

Post-build validation

Manifest push and notifications

📄 Manifest & State Tracking
manifest.json: AMI build metadata

terraform.tfstate: IAM OIDC state tracking

variables.pkr.hcl.bak: Backup of build variables
