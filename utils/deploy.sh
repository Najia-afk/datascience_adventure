#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to restart a service if it is running, otherwise start it
restart_or_start_service() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name"; then
        echo "$service_name is running. Restarting $service_name..."
        sudo systemctl restart "$service_name"
    else
        echo "$service_name is not running. Starting $service_name..."
        sudo systemctl start "$service_name"
    fi
}

# Copy updated static files to the web directory
echo "Copying updated static files..."
sudo cp -r app/static/* /var/www/htmx_website/

# Copy updated Nginx configuration
echo "Copying updated Nginx configuration..."
sudo cp nginx/htmx_website /etc/nginx/sites-available/htmx_website

# Create a symbolic link if it doesn't already exist
if [ ! -L /etc/nginx/sites-enabled/htmx_website ]; then
    echo "Creating symbolic link for Nginx configuration..."
    sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
fi

# Refresh Nginx configuration
echo "Refreshing Nginx configuration..."
sudo nginx -t && sudo systemctl reload nginx

# Restart or start the Gunicorn service managed by systemd
echo "Restarting or starting the Gunicorn service..."
restart_or_start_service "htmx_website.service"

# Function to convert Jupyter notebooks to HTML
convert_notebooks() {
    local notebook_dir=$1
    local output_dir=$2

    echo "Converting notebooks in $notebook_dir to HTML..."
    mkdir -p "$output_dir"
    for notebook in "$notebook_dir"/*.ipynb; do
        if [ -f "$notebook" ]; then
            jupyter nbconvert --to html "$notebook" --output-dir "$output_dir" || {
                echo "Failed to convert $notebook. Skipping..."
                continue
            }
            echo "Converted: $notebook"
        else
            echo "No notebooks found in $notebook_dir."
        fi
    done
}

# Function to configure Sphinx and generate HTML documentation for Python scripts
generate_script_docs() {
    local scripts_dir=$1
    local output_dir=$2

    echo "Generating HTML documentation for scripts in $scripts_dir using Sphinx..."
    
    # Check if the scripts directory exists
    if [ ! -d "$scripts_dir" ]; then
        echo "Scripts directory $scripts_dir does not exist. Skipping documentation generation."
        return
    fi

    # Navigate to the scripts directory
    cd "$scripts_dir" || exit

    # Initialize Sphinx if not already done
    if [ ! -d "docs" ]; then
        sphinx-quickstart --quiet -p "Script Documentation" -a "Author" -v 1.0 --ext-autodoc --ext-autosummary --makefile docs
        # Update Sphinx configuration to include Python source files and enable necessary extensions
        sed -i '1i\import sys, os' docs/conf.py
        sed -i "/sys\.path\.insert/a sys.path.insert(0, os.path.abspath('../'))" docs/conf.py
        sed -i "/extensions = \[/a 'sphinx.ext.autodoc', 'sphinx.ext.autosummary'," docs/conf.py
    fi

    # Automatically add all scripts to the index.rst file
    INDEX_RST="docs/source/index.rst"
    echo ".. toctree::" > "$INDEX_RST"
    echo "   :maxdepth: 2" >> "$INDEX_RST"
    echo "   :caption: Contents:" >> "$INDEX_RST"
    echo "" >> "$INDEX_RST"
    
    # List all Python scripts in the source folder
    for script in "$scripts_dir"/*.py; do
        script_name=$(basename "$script" .py)
        echo "   $script_name" >> "$INDEX_RST"
    done

    # Build the documentation
    sphinx-apidoc -o docs/source .
    make -C docs html || {
        echo "Failed to build documentation with Sphinx. Check the configuration."
        return
    }

    # Move the generated documentation to the output directory
    mv docs/_build/html/* "$output_dir/"
    echo "Generated docs in: $output_dir"

    # Go back to the original directory
    cd - || exit
}

# Function to place HTML files in Nginx HTML directory
place_files() {
    local source_dir=$1
    local destination_dir=$2

    echo "Copying HTML files from $source_dir to $destination_dir..."
    
    # Check if the source and destination are not the same before copying
    if [ "$source_dir" != "$destination_dir" ]; then
        sudo cp -r "$source_dir"/* "$destination_dir" || {
            echo "Failed to copy files from $source_dir to $destination_dir. Check permissions."
        }
    else
        echo "Source and destination directories are the same. Skipping copy operation."
    fi
}

# Main deployment logic
deploy() {
    # Define base directories
    BASE_DIR=$(dirname $(realpath "$0"))
    echo "BASE_DIR: $BASE_DIR"

    # Correct the project directory to the current working directory
    PROJECT_DIR=$(pwd)
    echo "PROJECT_DIR: $PROJECT_DIR"

    NGINX_HTML_DIR="/var/www/htmx_website"
    echo "NGINX_HTML_DIR: $NGINX_HTML_DIR"

    # Directory where HTML files are located
    HTML_DIR="$PROJECT_DIR/app/static"
    echo "HTML_DIR: $HTML_DIR"

    # Check if directories exist
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "Error: Project directory $PROJECT_DIR does not exist."
        exit 1
    fi

    if [ ! -d "$HTML_DIR" ]; then
        echo "Error: HTML directory $HTML_DIR does not exist."
        exit 1
    fi

    # Ensure required commands are available
    if ! command -v jupyter &> /dev/null || ! command -v sphinx-quickstart &> /dev/null; then
        echo "Error: Required commands 'jupyter' and 'Sphinx' are not installed."
        exit 1
    fi

    # Check each HTML file inside app/static for Colab links to determine corresponding mission directories
    for html_file in "$HTML_DIR/"*.html; do
        echo "Processing HTML file: $html_file"

        # Verify if the file exists before processing
        if [ ! -f "$html_file" ]; then
            echo "File $html_file does not exist. Skipping..."
            continue
        fi

        # Extract the Colab link to determine the mission path
        colab_link=$(grep -oP 'https://colab\.research\.google\.com/github/[^"]+' "$html_file" || true)

        # If a Colab link is found, parse it to find the mission directory
        if [ -n "$colab_link" ]; then
            echo "Found Colab link: $colab_link"

            # Extract the mission name and relevant paths
            mission_name=$(echo "$colab_link" | sed -E 's#.*/(mission[^/]+)/.*#\1#')
            notebook_path=$(echo "$colab_link" | sed -E 's#.*github/[^/]+/([^/]+)#\1#')
            mission_path="$HOME/$mission_name"
            notebook_dir="$mission_path"  # Assuming notebooks are at the root of the mission directory
            scripts_dir="$mission_path/src/scripts"
            output_dir="$NGINX_HTML_DIR/$mission_name"

            echo "Processing mission: $mission_name"
            echo "Mission path: $mission_path"
            echo "Notebook directory: $notebook_dir"
            echo "Scripts directory: $scripts_dir"

            # Check if the mission directory exists
            if [ -d "$mission_path" ]; then
                # Create the output directory if it does not exist
                sudo mkdir -p "$output_dir"
                sudo chown -R ubuntu:ubuntu "$output_dir"

                # Convert notebooks and generate script docs
                convert_notebooks "$notebook_dir" "$output_dir"
                generate_script_docs "$scripts_dir" "$output_dir"

                # Place files in Nginx directory
                place_files "$output_dir" "$NGINX_HTML_DIR/$mission_name"
            else
                echo "Mission directory $mission_path does not exist or is not accessible. Skipping..."
            fi
        else
            echo "No Colab link found in $html_file. Skipping..."
        fi
    done

    # Restart or start the Flask service
    echo "Restarting or starting the Flask service..."
    restart_or_start_service "htmx_website.service"

    # Restart or start Nginx to apply changes
    echo "Restarting or starting Nginx..."
    restart_or_start_service "nginx"

    # Output status of services
    echo "Checking the status of services..."
    sudo systemctl status nginx
    sudo systemctl status htmx_website.service

    echo "Deployment complete!"
}

# Execute the deployment process
deploy
