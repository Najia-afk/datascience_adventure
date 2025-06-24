#!/bin/bash

# Improved deployment script for public mission repos
# Version: 1.2.0

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

# User/group config
WEB_USER="www-data"
WEB_GROUP="www-data"
HTML_USER="ubuntu"

# Ensure HTML_USER is in WEB_GROUP for collaborative editing
if ! id -nG "$HTML_USER" | grep -qw "$WEB_GROUP"; then
    sudo usermod -aG "$WEB_GROUP" "$HTML_USER"
fi

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

# Set permissions for web files and collaborative editing
log "Setting proper permissions and group ownership..."
sudo chown -R $WEB_USER:$WEB_GROUP "$WWW_DIR" "$FLASK_DIR"
sudo chmod -R 2775 "$WWW_DIR" "$FLASK_DIR"   # Directories: setgid, group-writable
sudo find "$WWW_DIR" "$FLASK_DIR" -type d -exec chmod 2775 {} \;
sudo find "$WWW_DIR" "$FLASK_DIR" -type f -exec chmod 664 {} \;

# Make scripts executable if present
if [ -d "$FLASK_DIR/scripts" ]; then
    sudo find "$FLASK_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
fi

VENV_DIR="$FLASK_DIR/venv"

# Create Python virtual environment if not exists
if [ ! -d "$VENV_DIR" ]; then
    log "Creating Python virtual environment in $VENV_DIR..."
    # Ensure python3-venv is installed
    if ! dpkg -s python3-venv >/dev/null 2>&1; then
        log "python3-venv not found. Installing..."
        sudo apt-get update
        sudo apt-get install -y python3-venv
    fi
    sudo python3 -m venv "$VENV_DIR"
    sudo chown -R $WEB_USER:$WEB_GROUP "$VENV_DIR"
fi

# Ensure pip is installed in the venv (fix for missing pip)
if [ ! -x "$VENV_DIR/bin/pip" ]; then
    log "pip not found in venv, installing ensurepip..."
    sudo $VENV_DIR/bin/python3 -m ensurepip --upgrade
    sudo $VENV_DIR/bin/pip install --upgrade pip
    sudo chown $WEB_USER:$WEB_GROUP "$VENV_DIR/bin/pip"
fi

# Install/update Python dependencies in venv (latest versions, ignore requirements.txt)
log "Installing latest Python dependencies in venv..."
sudo -u $WEB_USER $VENV_DIR/bin/pip install --upgrade pip
sudo -u $WEB_USER $VENV_DIR/bin/pip install flask gunicorn dash

# Update Gunicorn service file with correct WSGI entry
if [ -f "$FLASK_DIR/.wsgi_entry" ]; then
    WSGI_ENTRY=$(cat "$FLASK_DIR/.wsgi_entry")
    log "Using WSGI entry point: $WSGI_ENTRY"
    
    GUNICORN_PATH="$VENV_DIR/bin/gunicorn"
    log "Using Gunicorn at: $GUNICORN_PATH"
    
    if [ ! -x "$GUNICORN_PATH" ]; then
        log "ERROR: Gunicorn not found or not executable at $GUNICORN_PATH. Installing..."
        sudo -u $WEB_USER $VENV_DIR/bin/pip install gunicorn
        if [ ! -x "$GUNICORN_PATH" ]; then
            log "ERROR: Failed to install gunicorn in venv. Exiting."
            exit 1
        fi
    fi
    
    log "Creating new systemd service file..."
    cat <<EOF | sudo tee /etc/systemd/system/htmx_website.service
[Unit]
Description=HTMX Website using Gunicorn and Flask
After=network.target

[Service]
User=$WEB_USER
Group=$WEB_GROUP
WorkingDirectory=$FLASK_DIR
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
