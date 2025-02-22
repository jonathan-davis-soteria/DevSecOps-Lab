#!/bin/bash
set -euxo pipefail

# Redirect all output to a log file
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "=== Starting User Data Script ==="

# Update required packages
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y docker.io python3 python3-pip

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
newgrp docker
sleep 10

# Install and start SSM agent
if ! snap list | grep -q amazon-ssm-agent; then
    sudo snap install amazon-ssm-agent --classic
fi
sudo systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service
sleep 10

echo "=== Configuring EBS Volume ==="

# Format the EBS volume only if not already formatted
if ! sudo file -s /dev/xvdf | grep -q 'ext4'; then
    echo "Formatting EBS volume..."
    sudo mkfs.ext4 /dev/xvdf
fi

# Create the mount point directory
sudo mkdir -p /opt/devsecops-blog/data

# Mount the volume
sudo mount /dev/xvdf /opt/devsecops-blog/data

# Ensure the volume mounts on reboot
echo '/dev/xvdf /opt/devsecops-blog/data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

# Set appropriate permissions
sudo chown -R ubuntu:ubuntu /opt/devsecops-blog/data
sudo chmod -R 755 /opt/devsecops-blog/data

echo "=== Docker login and pulling the new image ==="

# Docker login and pull the new image
echo "$DOCKER_PASSWORD" | sudo docker login -u "$DOCKER_USERNAME" --password-stdin
sudo docker pull simple-flask-blog:latest

echo "=== Stopping and removing any existing container ==="

# Stop and remove any existing container
sudo docker stop simple-flask-blog || true
sudo docker rm simple-flask-blog || true

echo "=== Running the new container ==="

# Run the new container with updated volume and environment variable
sudo docker run -d -p 80:5000 --restart unless-stopped --name simple-flask-blog \
  -v /opt/devsecops-blog/data:/app/instance \
  -e FLASK_SECRET_KEY="$FLASK_SECRET_KEY" \
  simple-flask-blog:latest

echo "=== User Data Script Completed Successfully ==="
