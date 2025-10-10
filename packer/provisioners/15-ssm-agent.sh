#!/bin/bash
# File: provisioners/15-ssm-agent.sh

set -e

echo "🔧 Installing SSM Agent..."

if [ -f /etc/os-release ]; then
  source /etc/os-release
  case "$ID" in
    amzn|rhel)
      sudo yum install -y amazon-ssm-agent
      ;;
    ubuntu)
      curl -Lo /tmp/ssm.deb https://s3.amazonaws.com/amazon-ssm-${AWS_REGION}/latest/debian_amd64/amazon-ssm-agent.deb
      sudo dpkg -i /tmp/ssm.deb
      ;;
  esac
fi

sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

echo "✅ SSM Agent installed and running."

