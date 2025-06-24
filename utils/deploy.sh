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
LOCAL_APP_DIR="$HOME/datascience_adventure/app"

sudo mkdir -p "$WWW_DIR"
sudo mkdir -p "$FLASK_DIR"
mkdir -p "$WORKDIR"

# Copy application files from local app directory
echo "Copying application files from $LOCAL_APP_DIR..."

# Copy static files from app/static directory if it exists
if [ -d "$LOCAL_APP_DIR/static" ]; then
    echo "Copying static files from app/static..."
    
    # Create necessary directories
    sudo mkdir -p "$WWW_DIR/templates"
    sudo mkdir -p "$WWW_DIR/styles"
    sudo mkdir -p "$WWW_DIR/logos"
    
    # Copy templates
    if [ -d "$LOCAL_APP_DIR/static/templates" ]; then
        sudo cp -r "$LOCAL_APP_DIR/static/templates/"* "$WWW_DIR/templates/" 2>/dev/null || true
        echo "Copied templates from app/static/templates"
    fi
    
    # Copy styles
    if [ -d "$LOCAL_APP_DIR/static/styles" ]; then
        sudo cp -r "$LOCAL_APP_DIR/static/styles/"* "$WWW_DIR/styles/" 2>/dev/null || true
        echo "Copied styles from app/static/styles"
    fi
    
    # Copy logos
    if [ -d "$LOCAL_APP_DIR/static/logos" ]; then
        sudo cp -r "$LOCAL_APP_DIR/static/logos/"* "$WWW_DIR/logos/" 2>/dev/null || true
        echo "Copied logos from app/static/logos"
    fi
    
    # Copy HTML files
    if [ -f "$LOCAL_APP_DIR/static/404.html" ]; then
        sudo cp "$LOCAL_APP_DIR/static/404.html" "$WWW_DIR/"
        echo "Copied 404.html from app/static"
    fi
    
    if [ -f "$LOCAL_APP_DIR/static/index.html" ]; then
        sudo cp "$LOCAL_APP_DIR/static/index.html" "$WWW_DIR/"
        echo "Copied index.html from app/static"
    fi
fi

# Copy server.py and wsgi.py if they exist
if [ -f "$LOCAL_APP_DIR/server.py" ]; then
    sudo cp "$LOCAL_APP_DIR/server.py" "$FLASK_DIR/"
    echo "Copied server.py from app directory"
fi

if [ -f "$LOCAL_APP_DIR/wsgi.py" ]; then
    sudo cp "$LOCAL_APP_DIR/wsgi.py" "$FLASK_DIR/"
    echo "Copied wsgi.py from app directory"
fi

# Verify critical template files exist
echo "Verifying critical template files..."

# Check 404.html exists
if [ ! -f "$WWW_DIR/404.html" ]; then
    echo "WARNING: 404.html not found, creating a basic version..."
    cat <<EOF | sudo tee "$WWW_DIR/404.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 Not Found</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { font-size: 50px; }
        a { color: #3498db; text-decoration: none; }
    </style>
</head>
<body>
    <h1>404</h1>
    <p>Sorry, the page you are looking for does not exist.</p>
    <p><a href="/">Return to homepage</a></p>
</body>
</html>
EOF
    echo "Created basic 404.html"
fi

# Check index.html exists
if [ ! -f "$WWW_DIR/index.html" ]; then
    echo "WARNING: index.html not found, creating a basic version..."
    cat <<EOF | sudo tee "$WWW_DIR/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Datascience Adventure</title>
    <link rel="stylesheet" href="/styles/styles.css">
    <script src="https://unpkg.com/htmx.org@1.9.2"></script>
</head>
<body hx-boost="true">
    <div id="header" hx-get="/header" hx-target="#header" hx-trigger="load"></div>
    <main id="main-content" class="content">
        <div id="default-content" hx-get="/summary" hx-target="#main-content" hx-trigger="load"></div>
    </main>
    <div id="footer" hx-get="/footer" hx-target="#footer" hx-trigger="load"></div>
</body>
</html>
EOF
    echo "Created basic index.html"
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

echo "Deployment complete! Website should be accessible now."
