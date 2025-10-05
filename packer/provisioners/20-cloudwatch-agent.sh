#!/usr/bin/env bash
set -euo pipefail
echo "[20-cloudwatch-agent] Starting CloudWatch Agent install..."
echo "[20-cloudwatch-agent] ENVIRONMENT=${ENVIRONMENT:-undefined}, DISTRO=${DISTRO:-undefined}"

# ------------------------------------------------------------------------------
# Detect OS (fallback to /etc/os-release if DISTRO not provided)
# ------------------------------------------------------------------------------
if [[ -z "${DISTRO:-}" && -f /etc/os-release ]]; then
  . /etc/os-release
  DISTRO=$ID
  echo "[20-cloudwatch-agent] Detected OS: ${DISTRO}"
fi

# ------------------------------------------------------------------------------
# Install CloudWatch Agent by distro
# ------------------------------------------------------------------------------
case "$DISTRO" in
  al2023|amzn|amazon)
    echo "[20-cloudwatch-agent] Installing CloudWatch Agent on Amazon Linux 2023..."
    sudo dnf -y update -y
    sudo dnf -y install amazon-cloudwatch-agent || true
    ;;

  rhel9|rhel)
    echo "[20-cloudwatch-agent] Installing CloudWatch Agent on RHEL..."
    sudo dnf -y update -y
    sudo dnf -y install amazon-cloudwatch-agent || true
    ;;

  ubuntu)
    echo "[20-cloudwatch-agent] Installing CloudWatch Agent on Ubuntu..."
    sudo apt-get update -y
    sudo apt-get install -y amazon-cloudwatch-agent || true
    ;;

  *)
    echo "[20-cloudwatch-agent] Unsupported distro: ${DISTRO}. Skipping CloudWatch Agent install."
    exit 0
    ;;
esac

# ------------------------------------------------------------------------------
# Configure CloudWatch Agent (basic system metrics)
# ------------------------------------------------------------------------------
AGENT_DIR="/opt/aws/amazon-cloudwatch-agent"
CONFIG_FILE="${AGENT_DIR}/etc/amazon-cloudwatch-agent.json"

sudo mkdir -p "${AGENT_DIR}/etc"
sudo tee "${CONFIG_FILE}" >/dev/null <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "ImageId": "${aws:ImageId}",
      "InstanceType": "${aws:InstanceType}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      },
      "netstat": {
        "measurement": ["tcp_established", "tcp_time_wait"],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

# ------------------------------------------------------------------------------
# Enable and start the agent
# ------------------------------------------------------------------------------
echo "[20-cloudwatch-agent] Enabling and starting amazon-cloudwatch-agent..."
sudo systemctl enable amazon-cloudwatch-agent || true
sudo systemctl restart amazon-cloudwatch-agent || true

# ------------------------------------------------------------------------------
# Verify status
# ------------------------------------------------------------------------------
if systemctl is-active --quiet amazon-cloudwatch-agent; then
  echo "[20-cloudwatch-agent] ✅ CloudWatch Agent running successfully."
else
  echo "[20-cloudwatch-agent] ⚠️ CloudWatch Agent failed to start. Check logs in /opt/aws/amazon-cloudwatch-agent/logs/"
fi

echo "[20-cloudwatch-agent] ✅ Completed CloudWatch Agent installation successfully."

