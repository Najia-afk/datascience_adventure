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

# Function to generate HTML documentation for Python scripts
generate_script_docs() {
    local scripts_dir=$1
    local output_dir=$2

    echo "Generating HTML documentation for scripts in $scripts_dir..."
    mkdir -p "$output_dir"
    for script in "$scripts_dir"/*.py; do
        if [ -f "$script" ]; then
            script_name=$(basename "$script" .py)
            pydoc -w "$script" || {
                echo "Failed to generate documentation for $script. Skipping..."
                continue
            }
            mv "$script_name.html" "$output_dir/"
            echo "Generated doc for: $script"
        else
            echo "No scripts found in $scripts_dir."
        fi
    done
}

# Function to place HTML files in Nginx HTML directory
place_files() {
    local source_dir=$1
    local destination_dir=$2

    echo "Copying HTML files from $source_dir to $destination_dir..."
    sudo cp -r "$source_dir"/* "$destination_dir" || {
        echo "Failed to copy files from $source_dir to $destination_dir. Check permissions."
    }
}

# Main deployment logic
deploy() {
    # Define base directories
    BASE_DIR=$(dirname $(realpath "$0"))
    MISSION_PARENT_DIR=$(dirname "$BASE_DIR")  # Parent directory of Datascience-Adventure and missions
    NGINX_HTML_DIR="/var/www/htmx_website"

    # Ensure required commands are available
    if ! command -v jupyter &> /dev/null || ! command -v pydoc &> /dev/null; then
        echo "Error: Required commands 'jupyter' and 'pydoc' are not installed."
        exit 1
    fi

    # Iterate over mission directories at the same level as Datascience-Adventure
    for mission in "$MISSION_PARENT_DIR"/mission*/; do
        mission_name=$(basename "$mission")
        notebook_dir="$mission"  # Assuming notebooks are in the root of each mission directory
        scripts_dir="$mission/src/scripts"
        output_dir="$NGINX_HTML_DIR/$mission_name"

        # Create the output directory if it does not exist
        sudo mkdir -p "$output_dir"
        sudo chown -R ubuntu:ubuntu "$output_dir"

        # Convert notebooks and generate script docs
        convert_notebooks "$notebook_dir" "$output_dir"
        generate_script_docs "$scripts_dir" "$output_dir"

        # Place files in Nginx directory
        place_files "$output_dir" "$NGINX_HTML_DIR/$mission_name"
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
