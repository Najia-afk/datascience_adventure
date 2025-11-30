#!/bin/bash
set -e

echo "=================================================="
echo "   Starting Docker Installation & Setup Script"
echo "=================================================="

# 1. Install Docker Prerequisites
echo ">>> Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg git

# 2. Add Docker's Official GPG Key
echo ">>> Adding Docker GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ -f /etc/apt/keyrings/docker.gpg ]; then
    sudo rm /etc/apt/keyrings/docker.gpg
fi
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 3. Add Docker Repository
echo ">>> Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Docker Engine
echo ">>> Installing Docker Engine..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Configure User Permissions
echo ">>> Adding user $USER to docker group..."
sudo usermod -aG docker $USER

# 6. Create Project Directory Structure
echo ">>> Setting up project directories..."
mkdir -p ~/projects
cd ~/projects

# 7. Clone Repositories
echo ">>> Cloning repositories..."
if [ ! -d "datascience_adventure" ]; then
    git clone https://github.com/Najia-afk/datascience_adventure.git
else
    echo "datascience_adventure already exists, pulling latest..."
    cd datascience_adventure && git pull && cd ..
fi

if [ ! -d "mission7" ]; then
    git clone https://github.com/Najia-afk/mission7.git
else
    echo "mission7 already exists, pulling latest..."
    cd mission7 && git pull && cd ..
fi

# 8. Create Shared Network
echo ">>> Creating shared Docker network..."
# Check if network exists first to avoid error
if ! sudo docker network ls | grep -q "web_network"; then
    sudo docker network create web_network
    echo "Network 'web_network' created."
else
    echo "Network 'web_network' already exists."
fi

# 9. Stop conflicting services (if any)
echo ">>> Stopping potential conflicting services (nginx, apache)..."
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl disable nginx 2>/dev/null || true
sudo systemctl stop apache2 2>/dev/null || true
sudo systemctl disable apache2 2>/dev/null || true

echo "=================================================="
echo "   Installation Complete!"
echo "=================================================="
echo "IMPORTANT NEXT STEPS:"
echo "1. Log out and log back in to apply Docker group changes: 'exit' then SSH again."
echo "2. Configure secrets for Mission 7:"
echo "   cd ~/projects/mission7"
echo "   nano .env"
echo "   (Add: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, SECRET_KEY)"
echo "3. Start the services:"
echo "   cd ~/projects/mission7 && docker compose up -d --build"
echo "   cd ~/projects/datascience_adventure && docker compose up -d --build"
echo "=================================================="
