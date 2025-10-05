#!/usr/bin/env bash
set -euo pipefail
echo "[10-hardening] Basic CIS-ish hardening"

# Ensure important sysctl settings (non-disruptive)
sudo tee /etc/sysctl.d/99-hardening.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv6.conf.all.accept_redirects = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
EOF
sudo sysctl --system

# Restrict core dumps
echo "* hard core 0" | sudo tee /etc/security/limits.d/99-nocore.conf

# Ensure password policy (example; adjust to your standards)
sudo sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sudo sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

# Remove tools often flagged (optional)
sudo dnf -y remove telnet 2>/dev/null || true
sudo yum -y remove telnet 2>/dev/null || true

# Cloud-init cleanup (ensure fresh instances)
sudo cloud-init clean --logs || true

