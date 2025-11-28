#!/bin/bash
set -e

# Mock sudo to run commands directly (since we are root in Docker)
sudo() {
    if [ "$1" = "-u" ]; then
        shift 2
    fi
    "$@"
}

# Mock systemctl to do nothing
systemctl() {
    echo "Mock systemctl: $@"
}

# Export functions so they are available in subshells
export -f sudo
export -f systemctl

# Create necessary directories to match the expected structure
mkdir -p /var/www/htmx_website
mkdir -p /srv/htmx_website/venv/bin

# Symlink system python/pip to the venv location expected by scripts
ln -sf $(which python3) /srv/htmx_website/venv/bin/python3
ln -sf $(which pip3) /srv/htmx_website/venv/bin/pip

# Create symlink for the project structure expected by deploy.sh
ln -sf /app /root/datascience_adventure

# Mimic the initial setup from setup_htmx_website.sh
# Copy all app files to the deployment directory
cp -r /app/app/* /srv/htmx_website/

# Run the original deploy script
# We use 'yes' to bypass any potential prompts, though deploy.sh seems non-interactive
./utils/deploy.sh

# Fix permissions for the web directory to be readable by everyone (for Nginx)
chmod -R 755 /var/www/htmx_website
