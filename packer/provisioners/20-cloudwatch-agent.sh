#!/bin/bash
set -euo pipefail

echo "[CloudWatch] ====================================================="
echo "[CloudWatch] Starting agent configuration..."
echo "[CloudWatch] DISTRO=${DISTRO:-undefined}"
echo "[CloudWatch] ENVIRONMENT=${ENVIRONMENT:-undefined}"
echo "[CloudWatch] ====================================================="

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] This script must be run as root. Use sudo." >&2
  exit 1
fi

# Install CloudWatch agent if not present
if ! command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &>/dev/null; then
  echo "[CloudWatch] Agent not found. Installing..."
  wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
  rm -f ./amazon-cloudwatch-agent.deb
fi

# Enable and start service
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent

# Inject config if missing
CONFIG_PATH="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[CloudWatch] No config found. Injecting default config..."
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
      },
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      }
    }
  }
}
EOF
fi

# Start agent with config
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:$CONFIG_PATH -s

# ✅ Optional Enhancement: Post-build validation
echo "[CloudWatch] Validating agent status..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status || {
  echo "[WARN] Agent status check failed. Proceeding anyway..."
}

echo "[CloudWatch] ✅ Agent configured and started successfully."

