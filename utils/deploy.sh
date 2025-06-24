#!/bin/bash

# Simple deploy script for public mission repos
# No fallbacks - only copies existing files

set -e

# Get the correct user's home directory, even when running with sudo
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
else
    USER_HOME=$HOME
fi

# List of public GitHub repos to deploy
REPOS=(
    "https://github.com/Najia-afk/mission2"
    "https://github.com/Najia-afk/mission3"
    "https://github.com/Najia-afk/mission4"
    "https://github.com/Najia-afk/mission5"
)

# Directory to clone/pull repos
WORKDIR="$USER_HOME/missions"
WWW_DIR="/var/www/htmx_website"
FLASK_DIR="/srv/htmx_website"
LOCAL_APP_DIR="$USER_HOME/datascience_adventure/app"
LOCAL_STATIC_DIR="$LOCAL_APP_DIR/static"

echo "Using directories:"
echo "- User home: $USER_HOME"
echo "- App directory: $LOCAL_APP_DIR"
echo "- Static directory: $LOCAL_STATIC_DIR"

# Create necessary directories
sudo mkdir -p "$WWW_DIR/templates"
sudo mkdir -p "$WWW_DIR/styles"
sudo mkdir -p "$WWW_DIR/logos"
sudo mkdir -p "$FLASK_DIR"
mkdir -p "$WORKDIR"

echo "===== Deploying local app files ====="

# Copy template files using the proven manual approach that works
echo "Copying template files..."
if [ -d "$LOCAL_STATIC_DIR/templates" ]; then
    # Create the templates directory
    sudo mkdir -p "$WWW_DIR/templates"
    
    # Copy templates using the same command that works manually
    sudo cp -rv "$LOCAL_STATIC_DIR/templates/"* "$WWW_DIR/templates/"
    
    # Set permissions immediately after copy (important)
    sudo chown -R www-data:www-data "$WWW_DIR/templates/"
    sudo chmod -R 755 "$WWW_DIR/templates/"
    
    echo "✅ Copied templates to $WWW_DIR/templates/ and set permissions"
    
    # Verify templates were copied
    echo "Templates in $WWW_DIR/templates/:"
    ls -la "$WWW_DIR/templates/"
else
    echo "⚠️ ERROR: Templates directory not found at $LOCAL_STATIC_DIR/templates"
    # List the directories that exist to help with troubleshooting
    echo "Checking directory structure:"
    if [ -d "$USER_HOME/datascience_adventure" ]; then
        echo "✓ $USER_HOME/datascience_adventure exists"
        ls -la "$USER_HOME/datascience_adventure"
    else
        echo "✗ $USER_HOME/datascience_adventure does not exist"
    fi
    
    if [ -d "$LOCAL_APP_DIR" ]; then
        echo "✓ $LOCAL_APP_DIR exists"
        ls -la "$LOCAL_APP_DIR"
    else
        echo "✗ $LOCAL_APP_DIR does not exist"
    fi
    
    if [ -d "$LOCAL_STATIC_DIR" ]; then
        echo "✓ $LOCAL_STATIC_DIR exists"
        ls -la "$LOCAL_STATIC_DIR"
    else
        echo "✗ $LOCAL_STATIC_DIR does not exist"
    fi
    
    exit 1
fi

# Copy style files
if [ -d "$LOCAL_STATIC_DIR/styles" ]; then
    sudo cp -r "$LOCAL_STATIC_DIR/styles/"* "$WWW_DIR/styles/" 2>/dev/null || true
    echo "✅ Copied styles from $LOCAL_STATIC_DIR/styles/"
fi

# Copy logo files
if [ -d "$LOCAL_STATIC_DIR/logos" ]; then
    sudo cp -r "$LOCAL_STATIC_DIR/logos/"* "$WWW_DIR/logos/" 2>/dev/null || true
    echo "✅ Copied logos from $LOCAL_STATIC_DIR/logos/"
fi

# Copy HTML files
if [ -f "$LOCAL_STATIC_DIR/404.html" ]; then
    sudo cp "$LOCAL_STATIC_DIR/404.html" "$WWW_DIR/"
    echo "✅ Copied 404.html from $LOCAL_STATIC_DIR/"
fi

if [ -f "$LOCAL_STATIC_DIR/index.html" ]; then
    sudo cp "$LOCAL_STATIC_DIR/index.html" "$WWW_DIR/"
    echo "✅ Copied index.html from $LOCAL_STATIC_DIR/"
fi

# Copy server.py and wsgi.py if they exist
if [ -f "$LOCAL_APP_DIR/server.py" ]; then
    sudo cp "$LOCAL_APP_DIR/server.py" "$FLASK_DIR/"
    echo "✅ Copied server.py from app directory"
fi

if [ -f "$LOCAL_APP_DIR/wsgi.py" ]; then
    sudo cp "$LOCAL_APP_DIR/wsgi.py" "$FLASK_DIR/"
    echo "✅ Copied wsgi.py from app directory"
fi

echo "===== Deploying remote repository files ====="

# Process remote repositories
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
        # Instead of just copying, we need to merge with the layout
        MISSION_NAME=$(basename "$HTML_FILE" .html)
        echo "Processing $MISSION_NAME HTML with layout template..."
        
        # Check if we have a layout template for this mission
        LAYOUT_FILE="$LOCAL_STATIC_DIR/${MISSION_NAME}_layout.html"
        if [ -f "$LAYOUT_FILE" ]; then
            echo "Found layout template for $MISSION_NAME"
            
            # Create temporary directory
            TMP_DIR=$(mktemp -d)
            
            # Copy the mission HTML to temp dir
            cp "$HTML_FILE" "$TMP_DIR/mission_content.html"
            
            # Extract the content from the mission HTML (between <body> and </body>)
            CONTENT=$(sed -n '/<body/,/<\/body>/p' "$TMP_DIR/mission_content.html")
            
            # Create the merged file by inserting content into iframe
            cat "$LAYOUT_FILE" > "$TMP_DIR/merged.html"
            
            # Add resize listener script to the merged file if not already present
            if ! grep -q "sendHeight" "$TMP_DIR/merged.html"; then
                sed -i '/<\/body>/i \
                <script>\
                    function sendHeight() {\
                        var documentHeight = document.body.scrollHeight;\
                        console.log("Iframe content height:", documentHeight);\
                        window.parent.postMessage({ height: documentHeight }, "*");\
                    }\
                    window.addEventListener("load", function() {\
                        sendHeight();\
                    });\
                    window.addEventListener("resize", function() {\
                        sendHeight();\
                    });\
                </script>' "$TMP_DIR/merged.html"
                echo "Added resize listener script to merged file"
            fi
            
            # Copy the merged file to the web directory
            sudo cp "$TMP_DIR/merged.html" "$WWW_DIR/${MISSION_NAME}.html"
            sudo cp "$HTML_FILE" "$WWW_DIR/${MISSION_NAME}_content.html"
            
            # Set proper permissions for both files
            sudo chown www-data:www-data "$WWW_DIR/${MISSION_NAME}.html"
            sudo chown www-data:www-data "$WWW_DIR/${MISSION_NAME}_content.html"
            sudo chmod 644 "$WWW_DIR/${MISSION_NAME}.html"
            sudo chmod 644 "$WWW_DIR/${MISSION_NAME}_content.html"
            
            # Clean up
            rm -rf "$TMP_DIR"
            
            echo "✅ Created merged ${MISSION_NAME}.html with layout in $WWW_DIR/"
        else
            # No layout template found, just copy the file as before
            sudo cp "$HTML_FILE" "$WWW_DIR/"
            echo "✅ Copied $(basename "$HTML_FILE") to $WWW_DIR/ (no layout template found)"
        fi
    else
        echo "No missionX.html found in $REPO_NAME"
    fi

    # Copy src directory
    if [ -d "$REPO_DIR/src" ]; then
        sudo rm -rf "$WWW_DIR/${REPO_NAME}_src"
        sudo cp -r "$REPO_DIR/src" "$WWW_DIR/${REPO_NAME}_src"
        echo "✅ Copied src/ to $WWW_DIR/${REPO_NAME}_src/"
    fi

    # Copy Flask files if present
    if [ -f "$REPO_DIR/app/server.py" ]; then
        sudo cp "$REPO_DIR/app/server.py" "$FLASK_DIR/server.py"
        echo "✅ Copied server.py to $FLASK_DIR/"
    fi
    
    if [ -f "$REPO_DIR/app/wsgi.py" ]; then
        sudo cp "$REPO_DIR/app/wsgi.py" "$FLASK_DIR/wsgi.py"
        echo "✅ Copied wsgi.py to $FLASK_DIR/"
    fi

    # Copy Nginx config if present
    if [ -f "$REPO_DIR/nginx/htmx_website" ]; then
        sudo cp "$REPO_DIR/nginx/htmx_website" /etc/nginx/sites-available/htmx_website
        sudo ln -sf /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/htmx_website
        echo "✅ Copied Nginx config to /etc/nginx/sites-available/htmx_website"
    fi
done

echo "===== Finalizing deployment ====="

# Set permissions for web files
sudo chown -R www-data:www-data "$WWW_DIR"
sudo chown -R www-data:www-data "$FLASK_DIR"
sudo chmod -R 755 "$WWW_DIR"
sudo chmod -R 755 "$FLASK_DIR"

# Ensure gunicorn is executable
if [ -f "$FLASK_DIR/venv/bin/gunicorn" ]; then
    sudo chmod +x "$FLASK_DIR/venv/bin/gunicorn"
    sudo chmod +x "$FLASK_DIR/venv/bin/python3"
    echo "✅ Set executable permissions for gunicorn and python"
elif [ -f "/srv/htmx_website/venv/bin/gunicorn" ]; then
    sudo chmod +x /srv/htmx_website/venv/bin/gunicorn
    sudo chmod +x /srv/htmx_website/venv/bin/python3
    echo "✅ Set executable permissions for gunicorn and python (alternate path)"
fi

# Reload services
sudo systemctl daemon-reload
echo "✅ Reloaded systemd daemon"

sudo systemctl restart htmx_website.service || echo "⚠️ Warning: Failed to restart htmx_website service"
echo "✅ Attempted to restart Flask application"

sudo systemctl reload nginx || echo "⚠️ Warning: Failed to reload nginx"
echo "✅ Reloaded Nginx"

echo "===== Deployment complete! ====="
echo "Website should now be accessible."
