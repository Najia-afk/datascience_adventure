#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

BASE_DIR="$HOME"  # Base directory where all projects are located
VENV_DIR="/srv/htmx_website/venv"  # Fixed virtual environment path
LOG_FILE="$HOME/log/htmx_deploy.log"  # Centralized log file

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
    pip install -r "$git /requirements_temp.txt" || {
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

        if [ -f "$html_file" ]; then
            colab_link=$(grep -oP 'https://colab\.research\.google\.com/github/[^"]+' "$html_file" || true)

            if [ -n "$colab_link" ]; then
                mission_name=$(echo "$colab_link" | sed -E 's#.*/(mission[^/]+)/.*#\1#')
                mission_path="$BASE_DIR/$mission_name"
                notebook_dir="$mission_path"
                scripts_dir="$mission_path/src/scripts"
                output_dir="$nginx_html_dir/$mission_name"

                log "Processing mission: $mission_name"
                if [ -d "$mission_path" ]; then
                    sudo mkdir -p "$output_dir"
                    set_permissions "$output_dir" "www-data:www-data"
                    convert_notebooks "$notebook_dir" "$output_dir"
                    update_sphinx_docs "$scripts_dir" "$output_dir"
                    embed_notebook_into_layout "$output_dir"
                    place_files "$output_dir" "$nginx_html_dir/$mission_name"
                else
                    log "Mission directory $mission_path does not exist or is not accessible. Skipping..."
                fi
            else
                log "No Colab link found in $html_file. Skipping..."
            fi
        else
            log "File $html_file does not exist. Skipping..."
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

# Main deployment function
deploy() {
    # Loop through all directories matching the pattern (e.g., mission*, toto*, etc.)
    for project_dir in "$BASE_DIR"/mission* "$BASE_DIR"/toto*; do
        [ -d "$project_dir" ] && process_project "$project_dir" || log "Skipping non-directory: $project_dir"
    done
}

# Execute the deployment process for all projects
deploy
