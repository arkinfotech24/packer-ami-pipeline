#!/usr/bin/env bash
set -euo pipefail
echo "[20-cloudwatch-agent] Installing CW Agent"

# Amazon Linux & RHEL both supported via yum/dnf repo
if command -v dnf >/dev/null 2>&1; then
  sudo dnf -y install amazon-cloudwatch-agent
elif command -v yum >/dev/null 2>&1; then
  sudo yum -y install amazon-cloudwatch-agent
fi

sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json >/dev/null <<'JSON'
{
  "metrics": {
    "append_dimensions": {
      "ImageId": "${aws:ImageId}",
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    },
    "metrics_collected": { "mem": { "measurement": ["mem_used_percent"] }, "cpu": { "measurement": ["cpu_usage_idle","cpu_usage_user","cpu_usage_system"] } }
  },
  "logs": { "logs_collected": { "files": { "collect_list": [{ "file_path": "/var/log/messages", "log_group_name": "/ec2/messages" }] } } }
}
JSON

sudo systemctl enable amazon-cloudwatch-agent || true

