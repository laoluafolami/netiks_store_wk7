#!/bin/bash
# This script runs automatically on the VM's first boot.
# We use 'DEBIAN_FRONTEND=noninteractive' to prevent apt from pausing for user input.
export DEBIAN_FRONTEND=noninteractive

# 1. Update the operating system
apt-get update -y
apt-get upgrade -y

# 2. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# 3. Add the default 'azureuser' and the new 'deploy' user to the docker group
# This allows them to run docker commands without 'sudo'
usermod -aG docker azureuser

# 4. Install Docker Compose plugin
apt-get install -y docker-compose-plugin

# 5. Install Node.js 20 (Required for the seed script)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# 6. Install Nginx and Git
apt-get install -y nginx git

# 7. Enable and start Nginx so it runs on boot
systemctl enable nginx
systemctl start nginx

# 8. Create the dedicated 'deploy' user for GitHub Actions
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

# 9. Set up the .ssh directory for the deploy user
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

# 10. Pre-clone the repository (Since your repo is Public, this works without credentials)
sudo -u deploy git clone https://github.com/laoluafolami/netiks_store_wk7.git /home/deploy/netiks_store
sudo -u deploy git clone https://github.com/laoluafolami/netiks_store_wk7.git /home/deploy/netiks_store-staging

# Ensure the deploy user owns both directories
chown -R deploy:deploy /home/deploy/netiks_store
chown -R deploy:deploy /home/deploy/netiks_store-staging

# Clean up apt cache to save disk space
apt-get clean