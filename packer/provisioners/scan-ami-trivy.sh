#!/bin/bash
set -euo pipefail

# Usage:
# ./scan-ami-trivy.sh --prefix hardened- --region us-east-1

# -----------------------------
# Parse arguments
# -----------------------------
PREFIX=""
REGION="us-east-1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "Usage: ./scan-ami-trivy.sh --prefix <tag-prefix> [--region <region>]"
      exit 1
      ;;
  esac
done

if [[ -z "$PREFIX" ]]; then
  echo "❌ Tag prefix is required. Example: ./scan-ami-trivy.sh --prefix hardened- --region us-east-1"
  exit 1
fi

# ✅ Fix: Relax region format check to allow valid AWS regions
if ! [[ "$REGION" =~ ^[a-z]{2}-[a-z0-9-]+-\d$ ]]; then
  echo "❌ Invalid AWS region format: $REGION"
  exit 1
fi

# -----------------------------
# Discover AMIs by tag prefix
# -----------------------------
echo "🔍 Discovering AMIs with tag prefix: $PREFIX in region: $REGION..."

TAGGED_IMAGES=$(aws ec2 describe-images \
  --region "$REGION" \
  --owners self \
  --filters "Name=tag:Project,Values=packer-ami-pipeline" \
  --query "Images[?starts_with(Tags[?Key=='Name'].Value | [0], \`${PREFIX}\`)].{Name:Tags[?Key=='Name'].Value | [0], ImageId:ImageId}" \
  --output json)

if [[ "$TAGGED_IMAGES" == "[]" || -z "$TAGGED_IMAGES" ]]; then
  echo "⚠️ No AMIs found with prefix: $PREFIX"
  exit 0
fi

# -----------------------------
# Scan each discovered AMI
# -----------------------------
echo "$TAGGED_IMAGES" | jq -c '.[]' | while read -r image; do
  TAG=$(echo "$image" | jq -r '.Name')
  AMI_ID=$(echo "$image" | jq -r '.ImageId')

  echo "✅ Found AMI: $AMI_ID (Tag: $TAG)"

  echo "🚀 Starting Trivy scan for $TAG..."
  trivy vm \
    --scanners vuln \
    --aws-region "$REGION" \
    "ami:$AMI_ID" \
    --severity HIGH,CRITICAL \
    --format table \
    --output "trivy-report-${TAG}.txt"

  echo "✅ Scan complete. Report saved to trivy-report-${TAG}.txt"
done

