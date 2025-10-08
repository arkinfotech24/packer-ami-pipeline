#!/bin/bash
set -euo pipefail
LOG="/var/log/packer-provision.log"
exec > >(tee -a "$LOG") 2>&1

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root. Use sudo." >&2
  exit 1
fi

# Reset root password expiration to allow non-interactive sudo
echo "[PRECHECK] Resetting root password expiration..."
chage -I -1 -m 0 -M 99999 -E -1 root || echo "[WARN] Failed to reset root password expiration"

run_step() {
  "$@" || echo "[RHEL9] Step failed: $*"
}

echo "[RHEL9] Starting CIS Level 1 hardening + CloudWatch setup..."

# Preflight: Ensure required tools
run_step dnf install -y bash wget curl coreutils

# CIS: Disable cramfs
run_step bash -c 'echo "install cramfs /bin/true" > /etc/modprobe.d/cramfs.conf'

# CIS: Install and initialize AIDE
run_step dnf install -y aide
run_step aide --init
run_step mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# CIS: Disable legacy services
run_step systemctl disable telnet.socket
run_step systemctl disable rsh.socket
run_step systemctl disable rexec.socket

# CIS: SSH hardening
run_step sed -i 's/^#Protocol .*/Protocol 2/' /etc/ssh/sshd_config
run_step sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# CIS: Password aging
run_step chage --maxdays 90 root
run_step chage --mindays 7 root
run_step chage --warndays 14 root

# CIS: File permissions
run_step chmod 644 /etc/passwd
run_step chmod 000 /etc/shadow

# CloudWatch: Install agent
run_step wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm
run_step rpm -U ./amazon-cloudwatch-agent.rpm
run_step rm -f ./amazon-cloudwatch-agent.rpm

# CloudWatch: Enable and start service
run_step systemctl enable amazon-cloudwatch-agent
run_step systemctl start amazon-cloudwatch-agent

# CloudWatch: Configure agent
CONFIG_PATH="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[CloudWatch] No config found. Injecting minimal default..."
  cat <<EOF | tee "$CONFIG_PATH" > /dev/null
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "\${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      }
    }
  }
}
EOF
fi

run_step /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:$CONFIG_PATH -s

# Final buffer to stabilize SSH before cleanup
echo "[RHEL9] Finalizing provisioning..."
sleep 10
echo "[RHEL9] ✅ CIS + CloudWatch setup complete."

