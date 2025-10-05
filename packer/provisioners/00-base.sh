#!/usr/bin/env bash
set -euo pipefail

echo "[00-base] ====================================================="
echo "[00-base] Starting base provisioning..."
echo "[00-base] ENVIRONMENT=${ENVIRONMENT:-undefined}"
echo "[00-base] DISTRO=${DISTRO:-undefined}"
echo "[00-base] ====================================================="

# ------------------------------------------------------------------------------
# Detect OS (in case DISTRO not passed from Packer)
# ------------------------------------------------------------------------------
if [[ -z "${DISTRO:-}" && -f /etc/os-release ]]; then
  . /etc/os-release
  DISTRO=$ID
  echo "[00-base] Auto-detected OS from /etc/os-release: ${DISTRO}"
fi

# ------------------------------------------------------------------------------
# Apply distro-specific base updates and packages (excluding kernel)
# ------------------------------------------------------------------------------
case "$DISTRO" in
  al2023|amzn|amazon)
    echo "[00-base] 🟦 Amazon Linux 2023 detected"
    echo "[00-base] Updating system packages (excluding kernel)..."
    sudo dnf -y update --exclude=kernel* || true
    sudo dnf -y install jq curl unzip tar --allowerasing || true
    ;;

  rhel9|rhel)
    echo "[00-base] 🟥 RHEL 9 detected"
    echo "[00-base] Updating system packages (excluding kernel)..."
    sudo dnf -y update --exclude=kernel* || true
    sudo dnf -y install jq curl unzip tar --allowerasing || true
    ;;

  ubuntu)
    echo "[00-base] 🟩 Ubuntu detected"
    echo "[00-base] Updating system packages (excluding kernel)..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -y
    # Hold kernel packages to avoid restarts and rebuilds
    sudo apt-mark hold linux-image-generic linux-headers-generic linux-image-* linux-headers-* || true
    sudo apt-get upgrade -y || true
    sudo apt-get install -y jq curl unzip tar || true
    ;;

  *)
    echo "[00-base] ⚠️ Unknown or unsupported distro: ${DISTRO}"
    echo "[00-base] Skipping base updates."
    ;;
esac

# ------------------------------------------------------------------------------
# SSH configuration tuning
# ------------------------------------------------------------------------------
echo "[00-base] Applying SSH keepalive configuration..."
sudo sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config || true
sudo sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config || true
sudo systemctl reload sshd || true

# ------------------------------------------------------------------------------
# Optional: Disable motd, banner, and cleanup unnecessary files
# ------------------------------------------------------------------------------
echo "[00-base] Performing system cleanup..."
sudo rm -rf /etc/motd.d/* /etc/issue.net /etc/issue 2>/dev/null || true

# ------------------------------------------------------------------------------
# Cleanup package caches to reduce AMI size
# ------------------------------------------------------------------------------
echo "[00-base] Cleaning up package caches..."
sudo dnf -y clean all 2>/dev/null || true
sudo yum -y clean all 2>/dev/null || true
sudo apt-get clean -y 2>/dev/null || true
sudo rm -rf /var/cache/{dnf,yum,apt}/* /tmp/* /var/tmp/* || true

echo "[00-base] ====================================================="
echo "[00-base] ✅ Completed base provisioning successfully."
echo "[00-base] ====================================================="

