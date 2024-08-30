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

# Function to update Sphinx documentation, fixing toctree warnings
update_sphinx_docs() {
    local scripts_dir=$1

    echo "Updating Sphinx documentation for scripts in $scripts_dir..."

    # Check if the scripts directory exists
    if [ ! -d "$scripts_dir" ]; then
        echo "Scripts directory $scripts_dir does not exist. Skipping documentation generation."
        return
    fi

    # Navigate to the docs directory
    local docs_dir="$scripts_dir/docs"
    mkdir -p "$docs_dir/source"

    # Initialize Sphinx if not already done
    if [ ! -f "$docs_dir/conf.py" ]; then
        sphinx-quickstart --quiet -p "Script Documentation" -a "Author" -v 1.0 --ext-autodoc --makefile "$docs_dir"
        sed -i '1i\import sys, os' "$docs_dir/conf.py"
        sed -i "/sys\.path\.insert/a sys.path.insert(0, os.path.abspath('../'))" "$docs_dir/conf.py"
    fi

    # Generate the .rst files for all Python scripts
    sphinx-apidoc -o "$docs_dir/source" "$scripts_dir"

    # Correctly generate index.rst with proper paths to avoid nested "source/source"
    {
        echo ".. toctree::"
        echo "   :maxdepth: 2"
        echo "   :caption: Contents:"
        echo ""

        # List .rst files without the incorrect source/source prefix
        for rst_file in "$docs_dir/source/"*.rst; do
            rst_filename=$(basename "$rst_file" .rst)
            echo "   $rst_filename"
        done
    } > "$docs_dir/source/index.rst"

    # Clean previous builds to avoid conflicts and outdated files
    make -C "$docs_dir" clean

    # Build the documentation
    make -C "$docs_dir" html || {
        echo "Failed to build documentation with Sphinx. Check the configuration."
        return
    }

    echo "Documentation updated successfully."
}


# Function to place HTML files in Nginx HTML directory
place_files() {
    local source_dir=$1
    local destination_dir=$2

    echo "Copying HTML files from $source_dir to $destination_dir..."

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
                update_sphinx_docs "$scripts_dir"

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
