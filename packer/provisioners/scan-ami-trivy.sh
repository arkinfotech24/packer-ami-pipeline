#!/usr/bin/env bash
set -euo pipefail

# Default values
PREFIX=""
REGION=""

# Parse arguments
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
      exit 1
      ;;
  esac
done

# Validate inputs
if [[ -z "$PREFIX" ]]; then
  echo "❌ Tag prefix is required. Example: ./scan-ami-trivy.sh --prefix hardened- --region us-east-1"
  exit 1
fi

if [[ ! "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
  echo "❌ Invalid AWS region format: $REGION"
  exit 1
fi

# Confirm Trivy and AWS CLI are available
command -v trivy >/dev/null || { echo "❌ Trivy is not installed or not in PATH"; exit 1; }
command -v aws >/dev/null || { echo "❌ AWS CLI is not installed or not in PATH"; exit 1; }

# Resolve AMI ID by tag prefix
AMI_ID=$(aws ec2 describe-images \
  --region "$REGION" \
  --filters "Name=tag:Version,Values=$PREFIX*" \
  --query 'Images[0].ImageId' \
  --output text)

if [[ "$AMI_ID" == "None" ]]; then
  echo "❌ No AMI found with prefix: $PREFIX"
  exit 1
fi

echo "✅ Found AMI: $AMI_ID"

# Run Trivy scan
trivy image --input "$AMI_ID" --format table

echo "✅ Trivy scan completed for AMI: $AMI_ID"

