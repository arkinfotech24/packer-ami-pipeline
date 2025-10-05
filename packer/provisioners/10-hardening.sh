#!/usr/bin/env bash
set -euo pipefail
echo "[10-hardening] ENV=$ENVIRONMENT DISTRO=$DISTRO"

# Detect OS family
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_FAMILY=$ID
else
  OS_FAMILY="unknown"
fi

#########################################
# 1. System update and minimal cleanup
#########################################
echo "[10-hardening] Updating packages..."
if command -v dnf >/dev/null 2>&1; then
  sudo dnf -y update --security || true
  sudo dnf -y autoremove || true
  sudo dnf clean all
elif command -v yum >/dev/null 2>&1; then
  sudo yum -y update || true
  sudo yum -y autoremove || true
  sudo yum clean all
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
  sudo apt-get clean
fi

#########################################
# 2. Disable unnecessary services
#########################################
echo "[10-hardening] Disabling unused network services..."
for svc in avahi-daemon cups rpcbind nfs-server; do
  if systemctl list-unit-files | grep -q "^${svc}"; then
    sudo systemctl disable --now "${svc}" || true
  fi
done

#########################################
# 3. SSH hardening
#########################################
echo "[10-hardening] Applying SSH security baselines..."
SSHD_CONFIG="/etc/ssh/sshd_config"

sudo sed -i -E '
  s/^#?PasswordAuthentication.*/PasswordAuthentication no/;
  s/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/;
  s/^#?X11Forwarding.*/X11Forwarding no/;
  s/^#?MaxAuthTries.*/MaxAuthTries 3/;
  s/^#?ClientAliveInterval.*/ClientAliveInterval 300/;
  s/^#?ClientAliveCountMax.*/ClientAliveCountMax 2/;
' "$SSHD_CONFIG"

sudo systemctl reload sshd 2>/dev/null || true

#########################################
# 4. Filesystem and permissions
#########################################
echo "[10-hardening] Securing file permissions..."
sudo chmod 600 /etc/ssh/ssh_host_*key || true
sudo chmod 644 /etc/ssh/ssh_host_*key.pub || true
sudo chmod 600 /root/.ssh/authorized_keys 2>/dev/null || true

# Lock system accounts (except root)
echo "[10-hardening] Locking inactive system accounts..."
sudo awk -F: '($3 < 1000 && $1 != "root") {print $1}' /etc/passwd | while read -r user; do
  sudo usermod -L "$user" 2>/dev/null || true
done

#########################################
# 5. Enable auditing/logging (where supported)
#########################################
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^auditd"; then
  echo "[10-hardening] Enabling auditd..."
  sudo systemctl enable auditd || true
  sudo systemctl start auditd || true
fi

#########################################
# 6. Kernel parameters (basic network hardening)
#########################################
echo "[10-hardening] Applying sysctl hardening..."
cat <<'EOF' | sudo tee /etc/sysctl.d/99-custom-hardening.conf >/dev/null
# Disable IPv6 (optional)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Ignore broadcast pings
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable SYN cookies
net.ipv4.tcp_syncookies = 1

# Reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF

sudo sysctl --system || true

#########################################
# 7. Cleanup
#########################################
echo "[10-hardening] Cleaning build artifacts..."
sudo rm -rf /tmp/* /var/tmp/* || true
sudo find /var/log -type f -exec truncate -s 0 {} \; || true

echo "[10-hardening] Completed successfully!"

