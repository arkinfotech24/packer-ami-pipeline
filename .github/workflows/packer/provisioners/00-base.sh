#!/usr/bin/env bash
set -euo pipefail
echo "[00-base] ENV=$ENVIRONMENT DISTRO=$DISTRO"

if command -v dnf >/dev/null 2>&1; then
  sudo dnf -y update
  sudo dnf -y install jq curl unzip tar
elif command -v yum >/dev/null 2>&1; then
  sudo yum -y update
  sudo yum -y install jq curl unzip tar
else
  echo "No dnf/yum detected" >&2
fi

# Basic system tweaks (safe during build)
sudo sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config || true
sudo sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config || true
sudo systemctl reload sshd || true

# Reduce package caches
sudo dnf -y clean all 2>/dev/null || true
sudo yum -y clean all 2>/dev/null || true

