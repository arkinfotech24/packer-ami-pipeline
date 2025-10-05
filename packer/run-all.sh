#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------
VERSION="${1:-1.0.10}"                        # Pass version as argument or default to 1.0.10
VARS_FILE="vars/dev.pkrvars.hcl"              # Path to your vars file
LOG_DIR="logs"                                # Log directory for each build
PARALLEL="${PARALLEL:-false}"                 # Run in parallel if PARALLEL=true

mkdir -p "${LOG_DIR}"

echo "============================================================"
echo " 🚀 Starting Packer AMI builds (version: ${VERSION})"
echo "============================================================"
echo

# ------------------------------------------------------------------------------
# BUILD FUNCTIONS
# ------------------------------------------------------------------------------
run_build() {
  local DISTRO=$1
  echo "[+] Starting build for ${DISTRO}..."
  packer build \
    -timestamp-ui \
    -only="amazon-ebs.${DISTRO}" \
    -var-file="${VARS_FILE}" \
    -var "version=${VERSION}" . \
    | tee "${LOG_DIR}/${DISTRO}-${VERSION}.log"
  echo "[✓] Build complete for ${DISTRO} (logs in ${LOG_DIR}/${DISTRO}-${VERSION}.log)"
}

# ------------------------------------------------------------------------------
# MAIN LOGIC
# ------------------------------------------------------------------------------
if [[ "${PARALLEL}" == "true" ]]; then
  echo "[*] Running all builds in PARALLEL mode..."
  run_build "al2023" &
  run_build "rhel9" &
  run_build "ubuntu" &
  wait
else
  echo "[*] Running all builds SEQUENTIALLY..."
  run_build "al2023"
  run_build "rhel9"
  run_build "ubuntu"
fi

echo
echo "============================================================"
echo " ✅ All builds completed successfully!"
echo " Logs stored in: ${LOG_DIR}/"
echo "============================================================"

# ------------------------------------------------------------------------------
# OPTIONAL: COMMIT UPDATED MANIFEST TO GITHUB
# ------------------------------------------------------------------------------
if [[ -f manifest.json ]]; then
  echo "[+] Committing updated manifest.json..."
  git add manifest.json
  git commit -m "Update manifest.json for version ${VERSION}"
  git push origin master || echo "[!] Git push skipped (no credentials in local env)"
fi

