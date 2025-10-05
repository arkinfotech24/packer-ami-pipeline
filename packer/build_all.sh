#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# build_all.sh - Build all hardened AMIs (Amazon Linux 2023, RHEL9, Ubuntu)
# Author: Onyeisi Allen Efienokwu
# ------------------------------------------------------------------------------

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="${ROOT_DIR}/vars/dev.pkrvars.hcl"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "$LOG_DIR"

# ------------------------------------------------------------------------------
# VERSION CONTROL - Auto increment patch version (e.g., 1.0.1 -> 1.0.2)
# ------------------------------------------------------------------------------
VERSION_FILE="${ROOT_DIR}/version.txt"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "1.0.0" > "$VERSION_FILE"
fi

VERSION=$(cat "$VERSION_FILE")
IFS='.' read -r major minor patch <<< "$VERSION"
NEW_VERSION="${major}.${minor}.$((patch + 1))"
echo "$NEW_VERSION" > "$VERSION_FILE"

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="${LOG_DIR}/packer-build-${NEW_VERSION}-${TIMESTAMP}.log"

echo "📦 Starting AMI builds..."
echo "➡️  Version: ${NEW_VERSION}"
echo "➡️  Logging to: ${LOG_FILE}"
echo "------------------------------------------------------------"

# ------------------------------------------------------------------------------
# FUNCTION TO RUN PACKER BUILDS
# ------------------------------------------------------------------------------
build_ami() {
  local DISTRO=$1
  echo "🚀 Building AMI for: ${DISTRO}"

  if ! packer build -timestamp-ui \
    -only="amazon-ebs.${DISTRO}" \
    -var-file="${VARS_FILE}" \
    -var "version=${NEW_VERSION}" \
    -var "cwagent=false" \
    "${ROOT_DIR}" | tee -a "$LOG_FILE"; then
    echo "⚠️  ${DISTRO} build failed. Retrying once..."
    sleep 5
    packer build -timestamp-ui \
      -only="amazon-ebs.${DISTRO}" \
      -var-file="${VARS_FILE}" \
      -var "version=${NEW_VERSION}" \
      -var "cwagent=false" \
      "${ROOT_DIR}" | tee -a "$LOG_FILE"
  fi
}

# ------------------------------------------------------------------------------
# EXECUTE BUILDS
# ------------------------------------------------------------------------------
build_ami "al2023"
build_ami "rhel9"
build_ami "ubuntu"

echo "------------------------------------------------------------"
echo "✅ All AMI builds complete! Version: ${NEW_VERSION}"
echo "🪣 Log file saved at: ${LOG_FILE}"
echo "------------------------------------------------------------"

# ------------------------------------------------------------------------------
# OPTIONAL: UPLOAD MANIFEST TO S3
# ------------------------------------------------------------------------------
# MANIFEST="${ROOT_DIR}/manifest.json"
# if [[ -f "$MANIFEST" ]]; then
#   echo "📤 Uploading manifest to S3..."
#   aws s3 cp "$MANIFEST" "s3://ami-manifests-arkinfotech24-packer-ami-pipeline-us-east-1/" \
#     --region us-east-1
#   echo "✅ Manifest uploaded successfully!"
# fi

