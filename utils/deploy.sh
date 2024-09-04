#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

BASE_DIR="$HOME"  # Base directory where all projects are located
VENV_DIR="/srv/htmx_website/venv"  # Fixed virtual environment path
LOG_FILE="$HOME/log/htmx_deploy.log"  # Centralized log file

# Ensure log directory exists
mkdir -p "$HOME/log"

# Trap to catch errors and cleanup
trap 'cleanup_on_error' ERR

# Logging function with log levels
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$2] $1" | tee -a "$LOG_FILE"
}

cleanup_on_error() {
    log "An error occurred during the deployment. Please check the logs." "ERROR"
    deactivate_venv
    exit 1
}

# Function to activate the fixed virtual environment
activate_venv() {
    if [ -d "$VENV_DIR" ]; then
        log "Activating the virtual environment at $VENV_DIR..." "INFO"
        source "$VENV_DIR/bin/activate"
    else
        log "Error: Virtual environment not found at $VENV_DIR. Exiting." "ERROR"
        exit 1
    fi
}

# Function to deactivate the virtual environment
deactivate_venv() {
    if [[ "$VIRTUAL_ENV" != "" ]]; then
        log "Deactivating the virtual environment..." "INFO"
        deactivate
    fi
}

# Function to set permissions for directories and files
set_permissions() {
    local target_dir=$1
    local user_group=$2
    log "Setting permissions for $target_dir..." "INFO"

    sudo chown -R "$user_group" "$target_dir" || {
        log "Failed to change ownership of $target_dir for $user_group." "ERROR"
        exit 1
    }
    sudo find "$target_dir" -type d -exec chmod 755 {} \;
    sudo find "$target_dir" -type f -exec chmod 644 {} \;
}

# Function to restart or start a service
restart_or_start_service() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name"; then
        log "$service_name is running. Restarting $service_name..." "INFO"
        sudo systemctl restart "$service_name"
    else
        log "$service_name is not running. Starting $service_name..." "INFO"
        sudo systemctl start "$service_name"
    fi
}

# Function to process each project
process_project() {
    local project_dir="$1"
    local nginx_html_dir="$project_dir/nginx"
    local html_dir="$project_dir/app/static"

    log "Processing project: $project_dir" "INFO"

    # Activate the fixed virtual environment
    activate_venv

    pip install --upgrade pip

    # Create a temporary requirements file excluding pywin32
    grep -v '^pywin32' requirements.txt > requirements_temp.txt

    # Install necessary Python packages
    pip install -r requirements_temp.txt || {
        log "Failed to install some packages. Please check the virtual environment setup." "ERROR"
        deactivate_venv
        exit 1
    }

    # Clean up temporary file
    rm requirements_temp.txt

    deactivate_venv
    log "Python packages installed successfully for project: $project_dir." "INFO"

    # Copy static files and update Nginx configuration
    update_static_files_and_nginx "$project_dir" "$nginx_html_dir"
  

    # Process all HTML files in the static directory
    for html_file in "$html_dir/"*.html; do
        log "Processing HTML file: $html_file" "INFO"
        project_name=$(basename "$html_file" _layout.html)
        colab_link=$(grep -oP 'https://colab\.research\.google\.com/github/[^"]+' "$html_file" || true)

        if [ -n "$colab_link" ]; then
            project_path="$BASE_DIR/$project_name"
            notebook_dir="$project_path"
            set_permissions "$notebook_dir" "ubuntu:ubuntu"
            scripts_dir="$project_path/src/scripts"
            output_dir="$nginx_html_dir/$project_name"

            log "Processing project: $project_name" "INFO"
            if [ -d "$project_path" ]; then
                sudo mkdir -p "$output_dir"
                convert_notebooks "$notebook_dir" "$output_dir"
                update_sphinx_docs "$scripts_dir" "$output_dir"
                set_permissions "$nginx_html_dir" "ubuntu:ubuntu"
                embed_notebook_into_layout "$output_dir" "$html_file"
                place_files "$output_dir" "/var/www/htmx_website/$project_name"
            else
                log "Mission directory $project_path does not exist or is not accessible. Skipping..." "WARNING"
            fi
        else
            log "No Colab link found in $project_name. Skipping..." "INFO"
        fi
    done

    setup_flask_app
    # Restart services after deployment
    restart_or_start_service "htmx_website.service"
    restart_or_start_service "nginx"

    log "Deployment complete for project: $project_dir!" "INFO"
}

# Function to update Nginx static files and configuration
update_static_files_and_nginx() {
    local project_dir="$1"
    local nginx_html_dir="$2"
    local backup_timestamp=$(date +'%Y%m%d%H%M%S')

    log "Copying updated static files for project: $project_dir" "INFO"
    sudo cp -r "$project_dir/app/static/"* "$nginx_html_dir/"

    log "Backing up current Nginx configuration..." "INFO"
    if [ -f /etc/nginx/sites-available/htmx_website ]; then
        sudo cp /etc/nginx/sites-available/htmx_website /etc/nginx/sites-available/htmx_website.bak.$backup_timestamp
    fi

    log "Validating new Nginx configuration..." "INFO"
    if sudo nginx -t -c "$project_dir/nginx/htmx_website"; then
        log "New Nginx configuration is valid. Applying it now." "INFO"

        sudo cp "$project_dir/nginx/htmx_website" /etc/nginx/sites-available/htmx_website

        if [ ! -L /etc/nginx/sites-enabled/htmx_website ]; then
            log "Creating symbolic link for Nginx configuration..." "INFO"
            sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
        fi

        log "Reloading Nginx with the new configuration..." "INFO"
        sudo systemctl reload nginx
    else
        log "Error: New Nginx configuration is invalid. Reverting to the previous configuration." "ERROR"
        sudo cp /etc/nginx/sites-available/htmx_website.bak.$backup_timestamp /etc/nginx/sites-available/htmx_website
        sudo nginx -t && sudo systemctl reload nginx
    fi
}

# Function to set up the Flask application
setup_flask_app() {
    log "Stopping Flask service (htmx_website.service)..." "INFO"
    
    
    # Set appropriate permissions for the new configuration
    set_permissions /srv/htmx_website "www-data:www-data"
    set_permissions app/ "www-data:www-data"

    sudo -su www-data

    # Stop the Flask service before making changes
    sudo systemctl stop htmx_website.service || {
        log "Failed to stop htmx_website.service. Please check the service status." "ERROR"
        exit 1
    }

    # Backup the existing Flask configuration
    if [ -f /srv/htmx_website/server.py ]; then
        log "Backing up existing Flask configuration..." "INFO"
        sudo cp /srv/htmx_website/server.py /srv/htmx_website/server.py.bak || {
            log "Failed to backup the existing Flask configuration." "ERROR"
            exit 1
        }
    fi

    # Copy the new server.py configuration
    log "Copying new Flask configuration..." "INFO"
    sudo cp -r app/server.py /srv/htmx_website/server.py || {
        log "Failed to copy the new Flask configuration." "ERROR"
        restore_flask_config
        exit 1
    }

    # Validate the new Flask application by starting the service
    log "Starting Flask service (htmx_website.service) to validate the new configuration..." "INFO"
    if sudo systemctl start htmx_website.service; then
        log "Flask service started successfully with the new configuration." "INFO"
    else
        log "Error: Failed to start Flask service with the new configuration. Restoring the previous configuration..." "ERROR"
        restore_flask_config
        sudo systemctl start htmx_website.service || {
            log "Failed to start Flask service with the restored configuration. Please check the service status." "ERROR"
            exit 1
        }
    fi

    
}

# Function to restore the previous Flask configuration
restore_flask_config() {
    log "Restoring the previous Flask configuration..." "INFO"
    if [ -f /srv/htmx_website/server.py.bak ]; then
        sudo cp /srv/htmx_website/server.py.bak /srv/htmx_website/server.py || {
            log "Failed to restore the previous Flask configuration." "ERROR"
            exit 1
        }
        log "Previous Flask configuration restored successfully." "INFO"
    else
        log "No backup found to restore the previous Flask configuration." "ERROR"
        exit 1
    fi
}

# Function to convert Jupyter notebooks to HTML
convert_notebooks() {
    local notebook_dir=$1
    local output_dir=$2
    log "Converting notebooks in $notebook_dir to HTML in $output_dir" "INFO"

    if [ -d "$notebook_dir" ]; then
        activate_venv
        jupyter nbconvert --to html --output-dir="$output_dir" "$notebook_dir"/*.ipynb
        deactivate_venv
        log "Notebook conversion completed." "INFO"
    else
        log "Notebook directory $notebook_dir does not exist. Skipping conversion." "WARNING"
    fi
}

# Function to update Sphinx documentation
update_sphinx_docs() {
    local sphinx_dir=$1
    local output_dir=$2
    log "Updating Sphinx documentation from $sphinx_dir to $output_dir" "INFO"

    if [ -d "$sphinx_dir" ]; then
        (cd "$sphinx_dir" && make html)
        cp -r "$sphinx_dir/_build/html/"* "$output_dir/"
        log "Sphinx documentation updated successfully." "INFO"
    else
        log "Sphinx documentation directory $sphinx_dir does not exist. Skipping documentation update." "WARNING"
    fi
}

update_sphinx_docs() {
    local scripts_dir=$1
    local output_dir="$2/scripts"

    log "Updating Sphinx documentation from $sphinx_dir to $output_dir" "INFO"

    if [ ! -d "$scripts_dir" ]; then
        log "Sphinx documentation directory $sphinx_dir does not exist. Skipping documentation generation." "WARNING"
        return
    fi

    local docs_dir="$scripts_dir/docs"
    mkdir -p "$docs_dir/source"

    activate_venv
    export PYTHONPATH="$scripts_dir"

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




# Function to embed notebook into layout
embed_notebook_into_layout() {
    local output_dir=$1
    local layout_file=$2

    log "Embedding notebook files into layout $layout_file..." "INFO"

    notebook_files=$(find "$output_dir" -type f -name '*.html')

    for notebook_file in $notebook_files; do
        notebook_content=$(cat "$notebook_file")
        sed -i "/<!-- NOTEBOOK_PLACEHOLDER -->/r $notebook_file" "$layout_file"
    done

    log "Notebooks embedded into layout successfully." "INFO"
}

# Function to place final files into the destination directory
place_files() {
    local output_dir=$1
    local destination_dir=$2
    log "Placing files from $output_dir to $destination_dir" "INFO"

    sudo mkdir -p "$destination_dir"
    sudo cp -r "$output_dir"/* "$destination_dir/"
    log "Files placed into $destination_dir successfully." "INFO"
}

# Main script execution starts here
log "Starting deployment script..." "INFO"

# Process each project in the base directory
for project in "$BASE_DIR"/*; do
    if [ -d "$project" ]; then
        process_project "$project"
    fi
done

log "Deployment script completed successfully!" "INFO"
