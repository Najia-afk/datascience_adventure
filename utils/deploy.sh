#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

BASE_DIR="$HOME"  # Base directory where all projects are located
VENV_DIR="/srv/htmx_website/venv"  # Fixed virtual environment path
LOG_FILE="$HOME/log/htmx_deploy.log"  # Centralized log file

# Ensure log directory exists
mkdir -p "$HOME/log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to activate the fixed virtual environment
activate_venv() {
    if [ -d "$VENV_DIR" ]; then
        log "Activating the virtual environment at $VENV_DIR..."
        source "$VENV_DIR/bin/activate"
    else
        log "Error: Virtual environment not found at $VENV_DIR. Exiting."
        exit 1
    fi
}

# Function to deactivate the virtual environment
deactivate_venv() {
    if [[ "$VIRTUAL_ENV" != "" ]]; then
        log "Deactivating the virtual environment..."
        deactivate
    fi
}

# Function to set permissions for directories and files
set_permissions() {
    local target_dir=$1
    local user_group=$2
    log "Setting permissions for $target_dir..."

    sudo chown -R "$user_group" "$target_dir"
    sudo find "$target_dir" -type d -exec chmod 755 {} \;
    sudo find "$target_dir" -type f -exec chmod 644 {} \;
}

# Function to restart or start a service
restart_or_start_service() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name"; then
        log "$service_name is running. Restarting $service_name..."
        sudo systemctl restart "$service_name"
    else
        log "$service_name is not running. Starting $service_name..."
        sudo systemctl start "$service_name"
    fi
}

# Function to process each project
process_project() {
    local project_dir="$1"
    local nginx_html_dir="$project_dir/nginx"
    local html_dir="$project_dir/app/static"

    log "Processing project: $project_dir"

    # Activate the fixed virtual environment
    activate_venv

    pip install --upgrade pip

    # Create a temporary requirements file excluding pywin32
    grep -v '^pywin32' requirements.txt > requirements_temp.txt

    # Install necessary Python packages
    pip install -r requirements_temp.txt || {
        log "Failed to install some packages. Please check the virtual environment setup."
        deactivate_venv
        exit 1
    }

    # Clean up temporary file
    rm requirements_temp.txt

    deactivate_venv
    log "Python packages installed successfully for project: $project_dir."

    # Copy static files and update Nginx configuration
    update_static_files_and_nginx "$project_dir" "$nginx_html_dir"

    # Process all HTML files in the static directory
    for html_file in "$html_dir/"*.html; do
        log "Processing HTML file: $html_file"
        project_name=$(basename "$html_file" _layout.html)
        colab_link=$(grep -oP 'https://colab\.research\.google\.com/github/[^"]+' "$html_file" || true)

        if [ -n "$colab_link" ]; then
            project_path="$BASE_DIR/$project_name"
            notebook_dir="$project_path"
            scripts_dir="$project_path/src/scripts"
            output_dir="$nginx_html_dir/$project_name"

            log "Processing mission: $project_name"
            if [ -d "$project_path" ]; then
                sudo mkdir -p "$output_dir"
                set_permissions "$output_dir" "www-data:www-data"
                convert_notebooks "$notebook_dir" "$output_dir"
                update_sphinx_docs "$scripts_dir" "$output_dir"
                embed_notebook_into_layout "$output_dir" "$project_dir/app/static/$html_file"
                place_files "$output_dir" "$nginx_html_dir/$project_name"
            else
                log "Mission directory $project_path does not exist or is not accessible. Skipping..."
            fi
        else
            log "No Colab link found in $project_name. Skipping..."
        fi
    done

    # Restart services after deployment
    restart_or_start_service "htmx_website.service"
    restart_or_start_service "nginx"

    log "Deployment complete for project: $project_dir!"
}

# Function to update Nginx static files and configuration
update_static_files_and_nginx() {
    local project_dir="$1"
    local nginx_html_dir="$2"

    log "Copying updated static files for project: $project_dir"
    sudo cp -r "$project_dir/app/static/"* "$nginx_html_dir/"
    set_permissions "$nginx_html_dir" "www-data:www-data"

    log "Validating new Nginx configuration..."
    if sudo nginx -t -c "$project_dir/nginx/htmx_website"; then
        log "New Nginx configuration is valid."

        if [ -f /etc/nginx/sites-available/htmx_website ]; then
            log "Backing up existing Nginx configuration..."
            sudo cp /etc/nginx/sites-available/htmx_website /etc/nginx/sites-available/htmx_website.bak
        fi

        sudo cp "$project_dir/nginx/htmx_website" /etc/nginx/sites-available/htmx_website

        if [ ! -L /etc/nginx/sites-enabled/htmx_website ]; then
            log "Creating symbolic link for Nginx configuration..."
            sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
        fi

        log "Testing and reloading Nginx..."
        if sudo nginx -t; then
            sudo systemctl reload nginx
        else
            log "Error: Nginx configuration test failed after copying the new configuration."
            log "Restoring the previous configuration..."
            sudo cp /etc/nginx/sites-available/htmx_website.bak /etc/nginx/sites-available/htmx_website
            sudo nginx -t && sudo systemctl reload nginx
        fi
    else
        log "Error: The new Nginx configuration is invalid. Falling back to the old configuration."
        [ ! -f /etc/nginx/sites-available/htmx_website ] && {
            sudo cp "$project_dir/nginx/htmx_website" /etc/nginx/sites-available/htmx_website
            [ ! -L /etc/nginx/sites-enabled/htmx_website ] && sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
        }
        sudo nginx -t && sudo systemctl reload nginx
    fi
}

# Function to convert Jupyter notebooks to HTML with additional debugging
convert_notebooks() {
    local notebook_dir=$1
    local output_dir=$2

    echo "Converting notebooks in $notebook_dir to HTML..."
    mkdir -p "$output_dir"

    # Set permissions to ensure the process can write to the output directory
    echo "Setting permissions for $output_dir..."
    sudo chown -R www-data:www-data "$output_dir"
    sudo chmod -R 775 "$output_dir"

    activate_venv

    # List all notebooks in the directory to confirm they exist
    echo "Listing notebooks in $notebook_dir:"
    ls -l "$notebook_dir"/*.ipynb

    for notebook in "$notebook_dir"/*.ipynb; do
        if [ -f "$notebook" ]; then
            echo "Converting $notebook..."

            # Use the full path to jupyter-nbconvert and sudo with environment preservation
            sudo -E /srv/htmx_website/venv/bin/jupyter-nbconvert "$notebook" --to html --output-dir "$output_dir" || {
                echo "Failed to convert $notebook due to permissions or other errors. Skipping..."
                continue
            }
            echo "Converted: $notebook to $output_dir"
        else
            echo "No notebooks found in $notebook_dir."
        fi
    done

    deactivate_venv

    # Reset permissions for security
    echo "Resetting permissions for $output_dir..."
    sudo chown -R www-data:www-data "$output_dir"
    sudo chmod -R 755 "$output_dir"
}

# Function to update Sphinx documentation
update_sphinx_docs() {
    local scripts_dir=$1
    local output_dir="$2/scripts"

    echo "Updating Sphinx documentation for scripts in $scripts_dir..."
    if [ ! -d "$scripts_dir" ]; then
        echo "Scripts directory $scripts_dir does not exist. Skipping documentation generation."
        return
    fi

    local docs_dir="$scripts_dir/docs"
    mkdir -p "$docs_dir/source"

    activate_venv
    export PYTHONPATH="$scripts_dir"  # Set PYTHONPATH to ensure imports work correctly

    if [ ! -f "$docs_dir/conf.py" ]; then
        sphinx-quickstart --quiet -p "Script Documentation" -a "Author" -v 1.0 --ext-autodoc --makefile "$docs_dir"
        sed -i '1i\import sys, os' "$docs_dir/conf.py"
        sed -i "/sys\.path\.insert/a sys.path.insert(0, os.path.abspath('../'))" "$docs_dir/conf.py"
    fi

    sphinx-apidoc -o "$docs_dir/source" "$scripts_dir"
    generate_index_rst "$docs_dir/source"

    make -C "$docs_dir" clean
    make -C "$docs_dir" html || {
        echo "Failed to build documentation with Sphinx. Check the configuration."
        deactivate_venv
        return
    }
    deactivate_venv

    move_generated_docs "$docs_dir/_build/html" "$output_dir"
}

# Function to generate a proper index.rst for Sphinx documentation
generate_index_rst() {
    local source_dir=$1

    # Check if the source directory exists
    if [ ! -d "$source_dir" ]; then
        echo "Source directory $source_dir does not exist. Skipping index generation."
        return
    fi

    echo "Generating index.rst in $source_dir..."

    # Create the index.rst file
    {
        echo ".. toctree::"
        echo "   :maxdepth: 2"
        echo "   :caption: Contents:"
        echo ""
    } > "$source_dir/index.rst"

    # Append .rst files to the index.rst
    for rst_file in "$source_dir/"*.rst; do
        rst_filename=$(basename "$rst_file" .rst)
        echo "   $rst_filename" >> "$source_dir/index.rst"
    done

    echo "index.rst generated successfully in $source_dir."
}

# Function to move generated documentation to the correct output directory
move_generated_docs() {
    local source_dir="$1"
    local destination_dir="$2"

    echo "Moving generated documentation from $source_dir to $destination_dir..."
    if [ -d "$destination_dir" ]; then
        echo "Cleaning existing directory $destination_dir..."
        sudo rm -rf "$destination_dir"/*  # Clean up the existing directory
    fi

    sudo mkdir -p "$destination_dir"
    sudo mv "$source_dir"/* "$destination_dir/"
    sudo chown -R www-data:www-data "$destination_dir"
    sudo find "$destination_dir" -type d -exec chmod 755 {} \;
    sudo find "$destination_dir" -type f -exec chmod 644 {} \;
    echo "Moved generated docs to: $destination_dir"
}

# Function to embed Jupyter notebooks into the layout
embed_notebook_into_layout() {
    local output_dir="$1"
    local layout_file="$2"  # Layout file passed as a parameter

    log "Embedding notebooks into layout using $layout_file"

    for notebook_html in "$output_dir"/*.html; do
        if [ -f "$notebook_html" ]; then
            local output_html="$output_dir/$(basename "$notebook_html")"
            log "Embedding $notebook_html into layout..."

            if [ -f "$layout_file" ]; then
                cat "$layout_file" "$notebook_html" > "$output_html" || {
                    log "Failed to embed $notebook_html into layout due to permission issues."
                    continue
                }
                log "Embedded $notebook_html into layout successfully."
            else
                log "Layout file $layout_file does not exist. Skipping embedding for $notebook_html."
            fi
        else
            log "No HTML files found in $output_dir."
        fi
    done
}

# Function to place files in the final destination
place_files() {
    local source_dir="$1"
    local destination_dir="$2"

    log "Placing files from $source_dir to $destination_dir..."
    if [ -d "$destination_dir" ]; then
        log "Cleaning existing directory $destination_dir..."
        sudo rm -rf "$destination_dir"/*  # Clean up the existing directory
    fi

    sudo mkdir -p "$destination_dir"
    sudo cp -r "$source_dir/"* "$destination_dir/"
    sudo chown -R www-data:www-data "$destination_dir"
    sudo find "$destination_dir" -type d -exec chmod 755 {} \;
    sudo find "$destination_dir" -type f -exec chmod 644 {} \;
    log "Files placed in: $destination_dir"
}

# Main deployment function
deploy() {
    # Loop through all directories matching the pattern (e.g., mission*, toto*, etc.)
    for project_dir in "$BASE_DIR"/datascience_adventure; do
        [ -d "$project_dir" ] && process_project "$project_dir" || log "Skipping non-directory: $project_dir"
    done
}

# Execute the deployment process for all projects
deploy
