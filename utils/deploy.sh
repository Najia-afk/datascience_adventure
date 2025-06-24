#!/bin/bash

# Improved deployment script for public mission repos
# Version: 1.1.0

set -e

# Config
REPOS=(
    "https://github.com/Najia-afk/mission2"
    "https://github.com/Najia-afk/mission3"
    "https://github.com/Najia-afk/mission4"
    "https://github.com/Najia-afk/mission5"
)

WORKDIR="$HOME/missions"
WWW_DIR="/var/www/htmx_website"
FLASK_DIR="/srv/htmx_website"
LOG_FILE="$HOME/deploy_log.txt"

# Logging function
log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log "ERROR: An error occurred at line $1. Exiting..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Create directories
log "Creating necessary directories..."
sudo mkdir -p "$WWW_DIR" "$WWW_DIR/mission_src"
sudo mkdir -p "$FLASK_DIR"
mkdir -p "$WORKDIR"

log "Starting deployment of mission repositories..."

for REPO_URL in "${REPOS[@]}"; do
    REPO_NAME=$(basename "$REPO_URL")
    REPO_DIR="$WORKDIR/$REPO_NAME"
    MISSION_NUM=$(echo "$REPO_NAME" | grep -o '[0-9]\+')

    log "Processing $REPO_NAME (Mission $MISSION_NUM)..."

    # Clone or pull repo
    if [ -d "$REPO_DIR/.git" ]; then
        log "Updating existing repository..."
        git -C "$REPO_DIR" pull --ff-only
    else
        log "Cloning new repository..."
        git clone "$REPO_URL" "$REPO_DIR"
    fi

    # Create mission-specific directories
    sudo mkdir -p "$WWW_DIR/mission${MISSION_NUM}"
    
    # Copy HTML files
    HTML_FILES=$(find "$REPO_DIR" -maxdepth 1 -iname "mission*.html")
    if [ -n "$HTML_FILES" ]; then
        for HTML_FILE in $HTML_FILES; do
            sudo cp "$HTML_FILE" "$WWW_DIR/"
            log "Copied $(basename "$HTML_FILE") to $WWW_DIR/"
        done
    else
        log "WARNING: No mission HTML files found in $REPO_NAME"
    fi

    # Copy src directory with better structure
    if [ -d "$REPO_DIR/src" ]; then
        log "Copying source files..."
        sudo rm -rf "$WWW_DIR/mission${MISSION_NUM}/src"
        sudo cp -r "$REPO_DIR/src" "$WWW_DIR/mission${MISSION_NUM}/src"
    fi

    # Copy additional assets if they exist
    for ASSET_DIR in "images" "data" "css" "js"; do
        if [ -d "$REPO_DIR/$ASSET_DIR" ]; then
            log "Copying $ASSET_DIR directory..."
            sudo mkdir -p "$WWW_DIR/mission${MISSION_NUM}/$ASSET_DIR"
            sudo cp -r "$REPO_DIR/$ASSET_DIR"/* "$WWW_DIR/mission${MISSION_NUM}/$ASSET_DIR/"
        fi
    done

    # Copy Flask files if present
    if [ -f "$REPO_DIR/app/server.py" ]; then
        log "Updating Flask server.py..."
        sudo cp "$REPO_DIR/app/server.py" "$FLASK_DIR/server.py"
        echo "server:app" | sudo tee "$FLASK_DIR/.wsgi_entry" > /dev/null
    fi
    
    if [ -f "$REPO_DIR/app/wsgi.py" ]; then
        log "Updating Flask wsgi.py..."
        sudo cp "$REPO_DIR/app/wsgi.py" "$FLASK_DIR/wsgi.py"
        echo "wsgi:app" | sudo tee "$FLASK_DIR/.wsgi_entry" > /dev/null
    fi

    # Copy Flask app directory if it exists
    if [ -d "$REPO_DIR/app" ]; then
        log "Syncing Flask application files..."
        # Create a list of files to exclude
        echo "server.py" > /tmp/exclude_list
        echo "wsgi.py" >> /tmp/exclude_list
        
        # Use rsync to copy only the new or changed files
        sudo rsync -av --exclude-from=/tmp/exclude_list "$REPO_DIR/app/" "$FLASK_DIR/"
        rm /tmp/exclude_list
    fi

    # Copy Nginx config if present
    if [ -f "$REPO_DIR/nginx/htmx_website" ]; then
        log "Updating Nginx configuration..."
        sudo cp "$REPO_DIR/nginx/htmx_website" /etc/nginx/sites-available/htmx_website
        sudo ln -sf /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/htmx_website
        
        # Validate Nginx config
        if sudo nginx -t; then
            log "Nginx configuration is valid."
        else
            log "ERROR: Invalid Nginx configuration. Reverting to previous config."
            sudo cp /etc/nginx/sites-available/htmx_website.bak /etc/nginx/sites-available/htmx_website
            sudo systemctl reload nginx
        fi
    fi
done

# Set permissions for web files
log "Setting proper permissions..."
sudo chown -R www-data:www-data "$WWW_DIR"
sudo chown -R www-data:www-data "$FLASK_DIR"
sudo find "$WWW_DIR" -type d -exec chmod 755 {} \;
sudo find "$WWW_DIR" -type f -exec chmod 644 {} \;
sudo find "$FLASK_DIR" -type d -exec chmod 755 {} \;
sudo find "$FLASK_DIR" -type f -exec chmod 644 {} \;

# Make scripts executable if present
if [ -d "$FLASK_DIR/scripts" ]; then
    sudo find "$FLASK_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
fi

# Update Gunicorn service file with correct WSGI entry
if [ -f "$FLASK_DIR/.wsgi_entry" ]; then
    WSGI_ENTRY=$(cat "$FLASK_DIR/.wsgi_entry")
    log "Using WSGI entry point: $WSGI_ENTRY"
    
    # Locate gunicorn - ensure we find the system one
    GUNICORN_PATH=$(command -v gunicorn || echo "/usr/bin/gunicorn")
    log "Using Gunicorn at: $GUNICORN_PATH"
    
    # Verify gunicorn exists and is executable
    if [ ! -x "$GUNICORN_PATH" ]; then
        log "ERROR: Gunicorn not found or not executable at $GUNICORN_PATH. Installing..."
        sudo apt-get update && sudo apt-get install -y gunicorn
        GUNICORN_PATH=$(command -v gunicorn || echo "/usr/bin/gunicorn")
        
        if [ ! -x "$GUNICORN_PATH" ]; then
            log "ERROR: Failed to install gunicorn. Exiting."
            exit 1
        fi
    fi
    
    # Create a new service file rather than trying to modify the existing one
    log "Creating new systemd service file..."
    cat <<EOF | sudo tee /etc/systemd/system/htmx_website.service
[Unit]
Description=HTMX Website using Gunicorn and Flask
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/srv/htmx_website
ExecStart=$GUNICORN_PATH --workers 5 --bind 127.0.0.1:8000 --timeout 120 $WSGI_ENTRY
Restart=always
Environment="PYTHONUNBUFFERED=1"
LimitNOFILE=4096
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    log "Systemd service file updated with correct gunicorn path: $GUNICORN_PATH"
fi

# Reload services
log "Reloading services..."
if sudo systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx
fi

if sudo systemctl is-active --quiet htmx_website.service; then
    sudo systemctl restart htmx_website.service
else
    sudo systemctl start htmx_website.service
fi

log "Deployment completed successfully!"
