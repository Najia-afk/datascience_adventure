#!/bin/bash

# Simple deploy script for public mission repos

set -e

# List of public GitHub repos to deploy (add more as needed)
REPOS=(
    "https://github.com/Najia-afk/mission2"
    "https://github.com/Najia-afk/mission3"
    "https://github.com/Najia-afk/mission4"
    "https://github.com/Najia-afk/mission5"
)

# Directory to clone/pull repos
WORKDIR="$HOME/missions"
WWW_DIR="/var/www/htmx_website"
FLASK_DIR="/srv/htmx_website"
LOCAL_STATIC_DIR="$HOME/datascience_adventure/app/static"

sudo mkdir -p "$WWW_DIR"
sudo mkdir -p "$FLASK_DIR"
mkdir -p "$WORKDIR"

# First copy local template and static files
if [ -d "$LOCAL_STATIC_DIR" ]; then
    echo "Copying local template and static files..."
    
    # Create necessary directories
    sudo mkdir -p "$WWW_DIR/templates"
    sudo mkdir -p "$WWW_DIR/styles"
    sudo mkdir -p "$WWW_DIR/logos"
    
    # Copy template files
    if [ -d "$LOCAL_STATIC_DIR/templates" ]; then
        sudo cp -r "$LOCAL_STATIC_DIR/templates/"* "$WWW_DIR/templates/" 2>/dev/null || true
        echo "Copied templates to $WWW_DIR/templates/"
    fi
    
    # Copy style files
    if [ -d "$LOCAL_STATIC_DIR/styles" ]; then
        sudo cp -r "$LOCAL_STATIC_DIR/styles/"* "$WWW_DIR/styles/" 2>/dev/null || true
        echo "Copied styles to $WWW_DIR/styles/"
    fi
    
    # Copy logo files
    if [ -d "$LOCAL_STATIC_DIR/logos" ]; then
        sudo cp -r "$LOCAL_STATIC_DIR/logos/"* "$WWW_DIR/logos/" 2>/dev/null || true
        echo "Copied logos to $WWW_DIR/logos/"
    fi
    
    # Copy important HTML files
    if [ -f "$LOCAL_STATIC_DIR/404.html" ]; then
        sudo cp "$LOCAL_STATIC_DIR/404.html" "$WWW_DIR/"
        echo "Copied 404.html to $WWW_DIR/"
    fi
    
    if [ -f "$LOCAL_STATIC_DIR/index.html" ]; then
        sudo cp "$LOCAL_STATIC_DIR/index.html" "$WWW_DIR/"
        echo "Copied index.html to $WWW_DIR/"
    fi
fi

# Then process remote repositories
for REPO_URL in "${REPOS[@]}"; do
    REPO_NAME=$(basename "$REPO_URL")
    REPO_DIR="$WORKDIR/$REPO_NAME"

    echo "Processing $REPO_NAME..."

    if [ -d "$REPO_DIR/.git" ]; then
        git -C "$REPO_DIR" pull --ff-only
    else
        git clone "$REPO_URL" "$REPO_DIR"
    fi

    # Copy missionX.html
    HTML_FILE=$(find "$REPO_DIR" -maxdepth 1 -iname "mission*.html" | head -n 1)
    if [ -f "$HTML_FILE" ]; then
        sudo cp "$HTML_FILE" "$WWW_DIR/"
        echo "Copied $(basename "$HTML_FILE") to $WWW_DIR/"
    else
        echo "No missionX.html found in $REPO_NAME"
    fi

    # Copy src directory
    if [ -d "$REPO_DIR/src" ]; then
        sudo rm -rf "$WWW_DIR/${REPO_NAME}_src"
        sudo cp -r "$REPO_DIR/src" "$WWW_DIR/${REPO_NAME}_src"
        echo "Copied src/ to $WWW_DIR/${REPO_NAME}_src/"
    else
        echo "No src/ directory found in $REPO_NAME"
    fi

    # Copy Flask files if present
    if [ -f "$REPO_DIR/app/server.py" ]; then
        sudo cp "$REPO_DIR/app/server.py" "$FLASK_DIR/server.py"
        echo "Copied server.py to $FLASK_DIR/"
    fi
    if [ -f "$REPO_DIR/app/wsgi.py" ]; then
        sudo cp "$REPO_DIR/app/wsgi.py" "$FLASK_DIR/wsgi.py"
        echo "Copied wsgi.py to $FLASK_DIR/"
    fi

    # Copy Nginx config if present
    if [ -f "$REPO_DIR/nginx/htmx_website" ]; then
        sudo cp "$REPO_DIR/nginx/htmx_website" /etc/nginx/sites-available/htmx_website
        sudo ln -sf /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/htmx_website
        echo "Copied Nginx config to /etc/nginx/sites-available/htmx_website"
    fi
done

# Set permissions for web files
sudo chown -R www-data:www-data "$WWW_DIR"
sudo chown -R www-data:www-data "$FLASK_DIR"
sudo chmod -R 755 "$WWW_DIR"
sudo chmod -R 755 "$FLASK_DIR"

# Ensure gunicorn is executable
if [ -f "/srv/htmx_website/venv/bin/gunicorn" ]; then
    sudo chmod +x /srv/htmx_website/venv/bin/gunicorn
    sudo chmod +x /srv/htmx_website/venv/bin/python3
    echo "Set executable permissions for gunicorn and python"
fi

# Reload Nginx and restart Flask service
sudo systemctl daemon-reload
sudo systemctl restart htmx_website.service || true

echo "Deployment complete."
