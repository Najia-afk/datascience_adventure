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
    
    # Install Pygments for syntax highlighting
    sudo -u www-data /srv/htmx_website/venv/bin/pip install pygments
    echo "✅ Installed Pygments for Python syntax highlighting"
fi

if [ -f "$LOCAL_APP_DIR/wsgi.py" ]; then
    sudo cp "$LOCAL_APP_DIR/wsgi.py" "$FLASK_DIR/"
    echo "✅ Copied wsgi.py from app directory"
fi

echo "===== Deploying remote repository files ====="

# Function to process mission HTML with layout template
process_mission_with_layout() {
    local html_file=$1
    local mission_name=$(basename "$html_file" .html)
    echo "Processing $mission_name HTML with layout template..."
    
    # Check if we have a specific layout template for this mission
    local layout_file="$LOCAL_STATIC_DIR/${mission_name}_layout.html"
    
    # If no specific layout exists, use the generic one
    if [ ! -f "$layout_file" ] && [ -f "$LOCAL_STATIC_DIR/mission_layout.html" ]; then
        echo "Using generic mission layout for $mission_name"
        layout_file="$LOCAL_STATIC_DIR/mission_layout.html"
    fi
    
    if [ -f "$layout_file" ]; then
        echo "Found layout template for $mission_name"
        
        # Create temporary directory
        local tmp_dir=$(mktemp -d)
        
        # Copy the mission HTML to temp dir
        cp "$html_file" "$tmp_dir/mission_content.html"
        
        # Look for scripts in the src directory for this mission
        local script_list=""
        local repo_name=$(basename $(dirname "$html_file"))
        local src_dir="$WORKDIR/$repo_name/src"
        
        if [ -d "$src_dir" ]; then
            echo "Generating script list from $src_dir"
            # Create a temporary script list file
            local script_list_file="$tmp_dir/script_list.html"
            echo '<ul id="sidebar-list">' > "$script_list_file"
            
            # Get all subdirectories in the src directory
            local subdirs=$(find "$src_dir" -type d | sort)
            
            # Process each subdirectory
            for subdir in $subdirs; do
                # Skip the src directory itself
                if [ "$subdir" = "$src_dir" ]; then
                    continue
                fi
                
                # Get the relative path from src
                local rel_path=${subdir#"$src_dir/"}
                # Only add subdir heading if files exist in this directory
                local has_py_files=$(find "$subdir" -maxdepth 1 -name "*.py" ! -name "__init__.py" | wc -l)
                
                if [ "$has_py_files" -gt 0 ]; then
                    # Add subdirectory heading
                    echo "<li class='subdir-heading'><strong>$(basename "$subdir")/</strong>" >> "$script_list_file"
                    echo "<ul>" >> "$script_list_file"
                    
                    # Find Python files in this subdirectory, excluding __init__.py
                    find "$subdir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | sort | while read script_path; do
                        local script_name=$(basename "$script_path")
                        # Create path relative to the mission directory - keep .py extension
                        local rel_script_path=${script_path#"$WORKDIR/$repo_name/"}
                        # Create proper URL to the Python file (not HTML)
                        local script_url="${repo_name}_src/${rel_script_path}"
                        # Remove trailing slashes and ensure clean URL path
                        script_url=$(echo "$script_url" | sed 's|//*|/|g')
                        echo "<li><a href=\"/$script_url\" target=\"_blank\">$script_name</a></li>" >> "$script_list_file"
                    done
                    
                    echo "</ul></li>" >> "$script_list_file"
                fi
            done
            
            # Also add Python files directly in the src directory
            local root_has_py_files=$(find "$src_dir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | wc -l)
            
            if [ "$root_has_py_files" -gt 0 ]; then
                echo "<li class='subdir-heading'><strong>root/</strong>" >> "$script_list_file"
                echo "<ul>" >> "$script_list_file"
                
                find "$src_dir" -maxdepth 1 -type f -name "*.py" ! -name "__init__.py" | sort | while read script_path; do
                    local script_name=$(basename "$script_path")
                    # Create correct URL to the Python file (not HTML)
                    local script_url="${repo_name}_src/$(basename "$script_path")"
                    # Clean up the URL path
                    script_url=$(echo "$script_url" | sed 's|//*|/|g')
                    echo "<li><a href=\"/$script_url\" target=\"_blank\">$script_name</a></li>" >> "$script_list_file"
                done
                
                echo "</ul></li>" >> "$script_list_file"
            fi
            
            echo '</ul>' >> "$script_list_file"
            script_list=$(cat "$script_list_file")
        else
            echo "No src directory found for $repo_name"
            # Default empty list
            script_list='<ul id="sidebar-list"><li>No scripts available</li></ul>'
        fi
        
        # Create a modified layout with the correct mission name and script list
        local modified_layout="$tmp_dir/modified_layout.html"
        cp "$layout_file" "$modified_layout"
        
        # Use more robust method to update mission number
        local mission_number=${mission_name#mission}
        # Update mission number in title tag
        sed -i "s/Mission: Data/Mission $mission_number: Data/g" "$modified_layout"
        # Update mission number in h1 tag
        sed -i "s/<h1>Mission: /<h1>Mission $mission_number: /g" "$modified_layout"
        
        # Create a script list placeholder file to avoid sed escaping issues
        echo "$script_list" > "$tmp_dir/script_list_content.html"
        
        # Use awk to replace the sidebar list - more reliable than sed for complex HTML
        awk '{
            if ($0 ~ /<ul id="sidebar-list">/) {
                system("cat '"$tmp_dir/script_list_content.html"'");
                in_list = 1;
            } else if (in_list && $0 ~ /<\/ul>/) {
                in_list = 0;
            } else if (!in_list) {
                print $0;
            }
        }' "$modified_layout" > "$tmp_dir/layout_with_scripts.html"
        
        # Move the modified file back
        mv "$tmp_dir/layout_with_scripts.html" "$modified_layout"
        
        # Update GitHub repo link
        local github_repo=$(echo "$repo_name" | tr '[:upper:]' '[:lower:]')
        sed -i "s|github.com/Najia-afk/mission|github.com/Najia-afk/$github_repo|g" "$modified_layout"
        
        # Update iframe src to point to the correct content file
        sed -i "s|id=\"main-iframe\" src=\"\"|id=\"main-iframe\" src=\"/${mission_name}_content.html\"|g" "$modified_layout"
        
        # Add resize listener script to the merged file if not already present
        if ! grep -q "sendHeight" "$modified_layout"; then
            cat <<EOF >> "$modified_layout"
<script>
    function sendHeight() {
        var documentHeight = document.body.scrollHeight;
        console.log("Iframe content height:", documentHeight);
        window.parent.postMessage({ height: documentHeight }, "*");
    }
    window.addEventListener("load", function() {
        sendHeight();
    });
    window.addEventListener("resize", function() {
        sendHeight();
    });
</script>
</body>
EOF
            # Remove the original closing body tag to avoid duplicates
            sed -i 's|</body>||g' "$modified_layout"
            # Add back the closing HTML tag if needed
            echo "</html>" >> "$modified_layout"
            echo "Added resize listener script to merged file"
        fi
        
        # Copy the modified layout and content to the web directory
        sudo cp "$modified_layout" "$WWW_DIR/${mission_name}.html"
        sudo cp "$html_file" "$WWW_DIR/${mission_name}_content.html"
        
        # Set proper permissions for both files
        sudo chown www-data:www-data "$WWW_DIR/${mission_name}.html"
        sudo chown www-data:www-data "$WWW_DIR/${mission_name}_content.html"
        sudo chmod 644 "$WWW_DIR/${mission_name}.html"
        sudo chmod 644 "$WWW_DIR/${mission_name}_content.html"
        
        # Clean up
        rm -rf "$tmp_dir"
        
        echo "✅ Created merged ${mission_name}.html with layout in $WWW_DIR/"
        return 0
    else
        # No layout template found
        echo "No layout template found for $mission_name"
        return 1
    fi
}

# Add this new function to convert Python files to HTML
convert_py_to_html() {
    local src_dir="$1"
    local dest_dir="$2"
    local repo_name="$3"
    
    echo "Converting Python files to HTML in $src_dir..."
    
    # Install pygments if not already installed
    if ! sudo -u www-data /srv/htmx_website/venv/bin/pip list | grep -q pygments; then
        sudo -u www-data /srv/htmx_website/venv/bin/pip install pygments
        echo "✅ Installed Pygments for Python syntax highlighting"
    fi
    
    # Find all Python files and convert them
    find "$src_dir" -type f -name "*.py" ! -name "__init__.py" | while read py_file; do
        # Get relative path
        rel_path=${py_file#"$src_dir/"}
        
        # Determine destination directory based on subdirectory name
        subdir=$(dirname "$rel_path")
        if [ "$subdir" = "." ]; then
            # Root directory files go to "root"
            target_dir="$dest_dir/root"
        else
            # Use the actual subdirectory name
            target_dir="$dest_dir/$subdir"
        fi
        
        # Create target directory if it doesn't exist
        sudo mkdir -p "$target_dir"
        
        # Get the basename without extension
        base_name=$(basename "$py_file" .py)
        html_file="$target_dir/${base_name}.html"
        
        echo "Converting $py_file to $html_file"
        
        # Read Python file
        py_content=$(cat "$py_file")
        
        # Generate HTML with Pygments using Python - with error handling
        html_content=$(sudo -u www-data /srv/htmx_website/venv/bin/python3 -c "
import pygments
import os
import sys
from pygments import highlight
from pygments.lexers import PythonLexer
from pygments.formatters import HtmlFormatter

code = '''$py_content'''

# Try to parse the Python code first to check for syntax errors
try:
    compile(code, '<string>', 'exec')
    is_valid = True
except SyntaxError as e:
    is_valid = False
    error_line = e.lineno
    error_msg = str(e)

if is_valid:
    # Code is valid, proceed with highlighting
    formatter = HtmlFormatter(style='default', linenos=True, full=True)
    html = highlight(code, PythonLexer(), formatter)
    css = formatter.get_style_defs('.highlight')
else:
    # Code has syntax errors, create a simpler display with error highlighted
    lines = code.split('\\n')
    html_lines = []
    
    for i, line in enumerate(lines, 1):
        if i == error_line:
            # Highlight the error line
            html_lines.append(f'<div class=\"error-line\">{i}: {line}</div>')
        else:
            html_lines.append(f'<div class=\"code-line\">{i}: {line}</div>')
    
    html = f'<div class=\"syntax-error\">SYNTAX ERROR: {error_msg}</div><pre>{\"\".join(html_lines)}</pre>'
    css = '.error-line { background-color: #ffcccc; color: #990000; } .syntax-error { color: red; font-weight: bold; margin-bottom: 10px; }'

print(f'''<!DOCTYPE html>
<html>
<head>
    <title>{os.path.basename('$py_file')}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 0; padding: 20px; }}
        .back-link {{ margin-bottom: 20px; }}
        .back-link a {{ text-decoration: none; color: #0066cc; }}
        .code-container {{ border: 1px solid #ddd; border-radius: 5px; overflow: auto; padding: 10px; }}
        .code-line {{ font-family: monospace; white-space: pre; }}
        {css}
    </style>
</head>
<body>
    <div class='back-link'>
        <a href='javascript:history.back()'>&lt; Back to mission</a>
    </div>
    <h2>{os.path.basename('$py_file')}</h2>
    <div class='code-container'>
        {html}
    </div>
</body>
</html>''')
" 2>/dev/null) || {
            # If Python script fails, create a simple error HTML file
            echo "⚠️ Error processing $py_file - syntax error detected"
            error_html="<!DOCTYPE html>
<html>
<head>
    <title>$(basename "$py_file") - Syntax Error</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .error { color: red; font-weight: bold; }
        .back-link { margin-bottom: 20px; }
        .back-link a { text-decoration: none; color: #0066cc; }
        pre { background-color: #f5f5f5; padding: 10px; border: 1px solid #ddd; border-radius: 5px; overflow: auto; }
    </style>
</head>
<body>
    <div class='back-link'>
        <a href='javascript:history.back()'>&lt; Back to mission</a>
    </div>
    <h2>$(basename "$py_file")</h2>
    <div class='error'>This file contains syntax errors and cannot be properly displayed.</div>
    <p>Please check the original source code for errors.</p>
    <pre>$(cat "$py_file" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')</pre>
</body>
</html>"
            echo "$error_html" | sudo tee "$html_file" > /dev/null
        }
        
        # Write HTML to file
        echo "$html_content" | sudo tee "$html_file" > /dev/null
        
        # Set proper permissions
        sudo chown www-data:www-data "$html_file"
        sudo chmod 644 "$html_file"
    done
    
    echo "✅ Converted Python files to HTML"
}

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
        # Use the function to process the mission with layout
        if ! process_mission_with_layout "$HTML_FILE"; then
            # If function returns non-zero (failed), fall back to simple copy
            sudo cp "$HTML_FILE" "$WWW_DIR/"
            echo "✅ Copied $(basename "$HTML_FILE") to $WWW_DIR/ (no layout template found)"
        fi
    else
        echo "No missionX.html found in $REPO_NAME"
    fi

    # Copy src directory - modify this section
    if [ -d "$REPO_DIR/src" ]; then
        echo "Processing source directory for $REPO_NAME..."
        
        # Create the destination directory
        sudo rm -rf "$WWW_DIR/${REPO_NAME}_src"
        sudo mkdir -p "$WWW_DIR/${REPO_NAME}_src"
        
        # Convert Python files to HTML and organize by subdirectory
        convert_py_to_html "$REPO_DIR/src" "$WWW_DIR/${REPO_NAME}_src" "$REPO_NAME"
        
        # Also copy the original Python files for reference
        sudo cp -r "$REPO_DIR/src" "$WWW_DIR/${REPO_NAME}_src_original"
        echo "✅ Processed src/ to $WWW_DIR/${REPO_NAME}_src/ and converted Python files to HTML"
    else
        echo "No src directory found in $REPO_NAME"
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
