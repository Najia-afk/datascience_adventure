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

# Validate article sidecar metadata before deployment
python3 /app/utils/scripts/validate_article_sidecars.py /app/app/static/templates

# Run the original deploy script
# We use 'yes' to bypass any potential prompts, though deploy.sh seems non-interactive
./utils/deploy.sh

# Ensure ALL templates are in /var/www/htmx_website/templates/
# (deploy.sh copies them, but as a safety net, copy again from source)
cp -rv /app/app/static/templates/* /var/www/htmx_website/templates/ 2>/dev/null || true

# Copy ALL generated content back to /srv/htmx_website/ so it's baked into the image.
# deploy.sh writes missions, scripts, etc. to /var/www/htmx_website/ but that path
# gets overlaid by the Docker volume at runtime. /srv/ survives and start_app.sh
# syncs it into the volume on each container start.
cp -a /var/www/htmx_website/. /srv/htmx_website/

# Fix permissions for the web directory to be readable by everyone (for Nginx)
chmod -R 755 /var/www/htmx_website
chmod -R 755 /srv/htmx_website
