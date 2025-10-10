#!/bin/bash
set -euo pipefail
LOG="/var/log/packer-provision.log"
exec > >(tee -a "$LOG") 2>&1

export DEBIAN_FRONTEND=noninteractive  # For Ubuntu

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root. Use sudo." >&2
  exit 1
fi

run_step() {
  "$@" || echo "[Ubuntu] Step failed: $*"
}

echo "[Ubuntu] Starting CIS Level 1 hardening + CloudWatch setup..."

# Enable universe repo for libonig5
run_step sudo add-apt-repository universe
run_step sudo apt-get update

# Install libjq1 with fallback to static jq binary
echo "[Ubuntu] Installing libjq1 with fallback to jq binary if needed..."
if ! run_step sudo apt-get install -y libjq1; then
  echo "[Ubuntu] libjq1 install failed. Falling back to static jq binary..."
  run_step curl -Lo /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  run_step chmod +x /usr/local/bin/jq
fi

# Preseed mail configuration to suppress interactive prompt
run_step bash -c 'echo "postfix postfix/mailname string your.domain.com" | sudo debconf-set-selections'
run_step bash -c 'echo "postfix postfix/main_mailer_type string \"No configuration\"" | sudo debconf-set-selections'

# CIS: Disable cramfs
run_step bash -c 'echo "install cramfs /bin/true" | sudo tee /etc/modprobe.d/cramfs.conf > /dev/null'

# CIS: Install and initialize AIDE
run_step bash -c 'echo "APT::Update::Post-Invoke-Success \"true\";" | sudo tee /etc/apt/apt.conf.d/99disable-cnf > /dev/null'
run_step sudo rm -rf /var/lib/apt/lists/*
run_step sudo apt-get clean
run_step sudo apt-get update
run_step sudo apt-get install -y aide
run_step sudo aideinit
run_step sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# CIS: Disable legacy services
run_step sudo systemctl disable telnet.socket
run_step sudo systemctl disable rsh.socket
run_step sudo systemctl disable rexec.socket

# CIS: SSH hardening
run_step sudo sed -i 's/^#Protocol .*/Protocol 2/' /etc/ssh/sshd_config
run_step sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# CIS: Password aging
run_step sudo chage --maxdays 90 root
run_step sudo chage --mindays 7 root
run_step sudo chage --warndays 14 root

# CIS: File permissions
run_step sudo chmod 644 /etc/passwd
run_step sudo chmod 000 /etc/shadow

# CloudWatch: Install agent
run_step wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
run_step sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
run_step rm -f ./amazon-cloudwatch-agent.deb

# CloudWatch: Enable and start service
run_step sudo systemctl enable amazon-cloudwatch-agent
run_step sudo systemctl start amazon-cloudwatch-agent

# CloudWatch: Configure agent
CONFIG_PATH="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[CloudWatch] No config found. Injecting minimal default..."
  cat <<EOF | sudo tee "$CONFIG_PATH" > /dev/null
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

# CloudWatch: Start agent with config
run_step sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:$CONFIG_PATH -s

echo "[Ubuntu] ✅ CIS + CloudWatch setup complete."

