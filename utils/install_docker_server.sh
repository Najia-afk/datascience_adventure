#!/bin/bash
set -e

echo "=================================================="
echo "   Starting Docker Installation & Setup Script"
echo "   For: Data Science Adventure Portfolio"
echo "=================================================="

# Configuration - can be overridden via environment variables
DOMAIN="${DOMAIN:-datascience-adventure.xyz}"
GITHUB_USER="${GITHUB_USER:-Najia-afk}"

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

# 5b. Configure Swap (Critical for 1GB RAM servers)
echo ">>> Checking for Swap space..."
if [ $(sudo swapon --show | wc -l) -eq 0 ]; then
    echo ">>> No swap detected. Creating 2GB swap file for 1GB RAM server..."
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo ">>> Swap created successfully."
else
    echo ">>> Swap already exists."
fi

# 6. Create Project Directory Structure
echo ">>> Setting up project directories..."
mkdir -p ~/projects
cd ~/projects

# 7. Clone Repositories
echo ">>> Cloning repositories..."
if [ ! -d "datascience_adventure" ]; then
    git clone https://github.com/${GITHUB_USER}/datascience_adventure.git
else
    echo "datascience_adventure already exists, pulling latest..."
    cd datascience_adventure && git pull && cd ..
fi

if [ ! -d "mission7" ]; then
    git clone https://github.com/${GITHUB_USER}/mission7.git
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

# 10. Create helper script to connect mission7 to web_network
echo ">>> Creating network connection helper script..."
cat > ~/projects/connect_mission7_network.sh << 'SCRIPT'
#!/bin/bash
# Connect mission7 containers to web_network (run after mission7 is started)
echo "Connecting mission7 containers to web_network..."

# Wait for containers to be running
sleep 5

# Connect nginx (required for proxying)
docker network connect web_network mission7_nginx_prod 2>/dev/null && \
    echo "✅ Connected mission7_nginx_prod to web_network" || \
    echo "ℹ️  mission7_nginx_prod already connected or not running"

# Connect mlflow (for /mission7/mlflow/ proxy)
docker network connect web_network mission7_mlflow_prod 2>/dev/null && \
    echo "✅ Connected mission7_mlflow_prod to web_network" || \
    echo "ℹ️  mission7_mlflow_prod already connected or not running"

echo "Done! Mission7 should now be accessible via datascience_adventure proxy."
SCRIPT
chmod +x ~/projects/connect_mission7_network.sh

echo "=================================================="
echo "   Installation Complete!"
echo "=================================================="
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Log out and log back in to apply Docker group changes:"
echo "   exit"
echo "   (then SSH back in)"
echo ""
echo "2. Configure Google OAuth for datascience_adventure:"
echo "   cd ~/projects/datascience_adventure"
echo "   # Option A: Create client_secret.json with your Google OAuth credentials"
echo "   # Option B: Create .env file with:"
echo "   #   GOOGLE_CLIENT_ID=your_client_id"
echo "   #   GOOGLE_CLIENT_SECRET=your_secret"
echo "   #   GOOGLE_REDIRECT_URI=https://${DOMAIN}/login"
echo "   #   ALLOWED_EMAILS=user1@gmail.com,user2@gmail.com"
echo "   #   SECRET_KEY=your_random_secret_key"
echo ""
echo "3. Start the services (ORDER MATTERS for first time):"
echo "   # Start mission7 first"
echo "   cd ~/projects/mission7"
echo "   docker compose -f docker-compose.prod.yml up -d --build"
echo ""
echo "   # Connect mission7 to web_network"
echo "   ~/projects/connect_mission7_network.sh"
echo ""
echo "   # Start datascience_adventure"
echo "   cd ~/projects/datascience_adventure"
echo "   docker compose up -d --build"
echo ""
echo "4. (Optional) Set up HTTPS with Let's Encrypt:"
echo "   cd ~/projects/datascience_adventure"
echo "   ./utils/setup_https.sh"
echo ""
echo "=================================================="
