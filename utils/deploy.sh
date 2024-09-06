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
    local website_html_dir="$project_dir/www"

    log "Processing project: $project_dir" "INFO"

    sudo chmod -R +x "$VENV_DIR"

    # Activate the fixed virtual environment
    # activate_venv

    # pip install --upgrade pip

    # Create a temporary requirements file excluding pywin32
    # grep -v '^pywin32' requirements.txt > requirements_temp.txt

    # Install necessary Python packages
    # pip install -r requirements_temp.txt || {
    #     log "Failed to install some packages. Please check the virtual environment setup." "ERROR"
        # deactivate_venv
        # exit 1
    # }

    # Clean up temporary file
    # rm requirements_temp.txt

    # deactivate_venv
    # log "Python packages installed successfully for project: $project_dir." "INFO"

    log "Processing project: $project_dir" "INFO"

    # Ensure the virtual environment is executable (if used)
    sudo chmod -R +x "$VENV_DIR"

    # Step 1: Set up permissions
    set_permissions "$nginx_html_dir" "ubuntu:ubuntu"
    set_permissions "$website_html_dir" "ubuntu:ubuntu"

    # Step 2: Clear existing static files in the website directory to avoid stale files
    sudo rm -rf "$website_html_dir/"*
    log "Cleared existing static files in $website_html_dir" "INFO"
    sudo rm -rf "/var/www/htmx_website/"*
    log "Cleared existing static files in /var/www/htmx_website/" "INFO"


    # Step 3: Copy updated static files to the website directory
    sudo mkdir -p "$website_html_dir"
    sudo mkdir -p "/var/www/htmx_website/templates"
    sudo mkdir -p "/var/www/htmx_website/styles"
    

    log "Copying static files from $html_dir to $website_html_dir" "INFO"
    
    sudo cp -r "$project_dir/app/static/templates/"* "/var/www/htmx_website/templates"
    sudo cp -r "$project_dir/app/static/styles/"* "/var/www/htmx_website/styles"

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
            scripts_dir="$project_path/src/scripts"
            output_dir="$website_html_dir/$project_name"

            log "Processing project: $project_name" "INFO"
            if [ -d "$project_path" ]; then
                sudo mkdir -p "$output_dir"
                convert_notebooks "$notebook_dir" "$output_dir"
                update_sphinx_docs "$scripts_dir" "$output_dir"
                embed_notebook_into_layout "$website_html_dir" "$html_file" "$project_name"
                place_files "$output_dir" "/var/www/htmx_website/$project_name"
            else
                log "Mission directory $project_path does not exist or is not accessible. Skipping..." "WARNING"
            fi
        else
            sudo cp "$html_file" "/var/www/htmx_website/$(basename "$html_file")"
            log "No Colab link found in $html_file. Skipping..." "INFO"
        fi
    done

    set_permissions "/var/www/htmx_website/" "www-data:www-data"
    deploy_flask_app "$project_dir"
    # Restart services after deployment
    restart_or_start_service "nginx"

    log "Deployment complete for project: $project_dir!" "INFO"
}

# Function to update Nginx static files and configuration
update_static_files_and_nginx() {
    local project_dir="$1"
    local nginx_html_dir="$2"
    local backup_timestamp=$(date +'%Y%m%d%H%M%S')

    log "Backing up current Nginx configuration..." "INFO"
    if [ -f /etc/nginx/sites-available/htmx_website ]; then
        sudo cp /etc/nginx/sites-available/htmx_website /etc/nginx/sites-available/htmx_website.bak.$backup_timestamp
    fi

    log "Validating new Nginx configuration..." "INFO"
    if sudo nginx -t -c /etc/nginx/nginx.conf; then
        log "New Nginx configuration is valid. Applying it now." "INFO"

        sudo cp "$project_dir/nginx/htmx_website" /etc/nginx/sites-available/htmx_website

        # Ensure symbolic link is updated correctly
        if [ ! -L /etc/nginx/sites-enabled/htmx_website ] || [ "$(readlink -f /etc/nginx/sites-enabled/htmx_website)" != "/etc/nginx/sites-available/htmx_website" ]; then
            log "Creating symbolic link for Nginx configuration..." "INFO"
            sudo ln -sf /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/htmx_website
        fi

        log "Reloading Nginx with the new configuration..." "INFO"
        sudo systemctl reload nginx
    else
        log "Error: New Nginx configuration is invalid. Reverting to the previous configuration." "ERROR"
        if [ -f /etc/nginx/sites-available/htmx_website.bak.$backup_timestamp ]; then
            sudo cp /etc/nginx/sites-available/htmx_website.bak.$backup_timestamp /etc/nginx/sites-available/htmx_website
        fi
        sudo nginx -t && sudo systemctl reload nginx
    fi
}


# Function to set up the Flask application
deploy_flask_app() {
    local project_dir="$1"
    local flask_app_dir="/srv/htmx_website"
    log "Stopping Flask service (htmx_website.service)..." "INFO"

    # Switch to the 'www-data' user to stop the service and handle file operations
    # Stop the Flask service before making changes
    sudo systemctl stop htmx_website.service || {
        log "Failed to stop htmx_website.service. Please check the service status." "ERROR" >&2
        exit 1
    }

    # Backup the existing Flask configuration
    if [ -f /srv/htmx_website/server.py ]; then
        log "Backing up existing Flask configuration..." "INFO" >&2
        sudo cp $flask_app_dir/server.py $flask_app_dir/server.py.bak || {
            log "Failed to backup the existing Flask configuration." "ERROR" >&2
            exit 1
        }
    fi

    # Copy the new server.py configuration
    echo "Copying new Flask configuration..." >&2
    sudo cp -r $project_dir/app/server.py $flask_app_dir/server.py || {
        log "Failed to copy the new Flask configuration." "ERROR" >&2
        exit 1
    }

    # Validate the new Flask application by starting the service
    log "Starting Flask service (htmx_website.service) to validate the new configuration..." "INFO" >&2
    if sudo systemctl start htmx_website.service; then
        log "Flask service started successfully with the new configuration." "INFO"  >&2
    else
        log "Error: Failed to start Flask service with the new configuration. Restoring the previous configuration..." "ERROR" >&2
        if [ -f /srv/htmx_website/server.py.bak ]; then
            sudo cp $flask_app_dir/server.py.bak $flask_app_dir/server.py || {
                log "Failed to restore the previous Flask configuration." "ERROR" >&2
                exit 1
            }
            log "Previous Flask configuration restored successfully." "INFO" >&2
        else
            log "No backup found to restore the previous Flask configuration." "ERROR" >&2
            exit 1
        fi
        sudo systemctl start htmx_website.service || {
            log "Failed to start Flask service with the restored configuration. Please check the service status." "ERROR" >&2
            exit 1
        }
    fi

    # Set appropriate permissions for the new configuration
    sudo chown www-data:www-data $flask_app_dir/server.py
    sudo chmod 644 $flask_app_dir/server.py
}

# Function to restore the previous Flask configuration
restore_flask_config() {
    log "Restoring the previous Flask configuration..." "INFO"
    if [ -f /srv/htmx_website/server.py.bak ]; then
        sudo cp $flask_app_dir/server.py.bak $flask_app_dir/server.py || {
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
        jupyter nbconvert --to html --output-dir="$output_dir" "$notebook_dir"/*.ipynb
        log "Notebook conversion completed." "INFO"
    else
        log "Notebook directory $notebook_dir does not exist. Skipping conversion." "WARNING"
    fi
}

# Function to update Sphinx documentation
update_sphinx_docs() {
    local scripts_dir=$1
    local output_dir="$2/scripts"

    log "Updating Sphinx documentation from $scripts_dir to $output_dir" "INFO"

    if [ ! -d "$scripts_dir" ]; then
        log "Sphinx documentation directory $scripts_dir does not exist. Skipping documentation generation." "WARNING"
        return
    fi

    local docs_dir="$scripts_dir/docs"
    mkdir -p "$docs_dir/source"

    # Ensure permissions for the docs directory
    set_permissions "$scripts_dir" "www-data:www-data"

    # Switch to 'www-data' user and execute the Sphinx commands
    activate_venv
    export PYTHONPATH="$scripts_dir"

    if [ ! -f "$docs_dir/conf.py" ]; then
        sphinx-quickstart --quiet -p "Script Documentation" -a "Author" -v 1.0 --ext-autodoc --makefile "$docs_dir"
        sed -i '1i\import sys, os' "$docs_dir/conf.py"
        sed -i "/sys\.path\.insert/a sys.path.insert(0, os.path.abspath('../'))" "$docs_dir/conf.py"
    fi

    sphinx-apidoc -o "$docs_dir/source" "$scripts_dir"

    # Ensure permissions for the docs directory
    set_permissions "$scripts_dir" "ubuntu:ubuntu"

    generate_index_rst "$docs_dir/source"

    make -C "$docs_dir" clean
    make -C "$docs_dir" html || {
        log "Failed to build documentation with Sphinx. Check the configuration." "WARNING"
        deactivate_venv
        exit 1
    }
    deactivate_venv


    # Switch back to the original user and move generated documentation
    move_generated_docs "$docs_dir/_build/html" "$output_dir"

}

# Function to generate a proper index.rst for Sphinx documentation
generate_index_rst() {
    local source_dir=$1

    # Check if the source directory exists
    if [ ! -d "$source_dir" ]; then
        log "Source directory $source_dir does not exist. Skipping index generation." "WARNING"
        return
    fi

    log "Generating index.rst in $source_dir..." "INFO"

    
    # Create the index.rst file
    {
        log ".. toctree::" "INFO"
        log "   :maxdepth: 2" "INFO"
        log "   :caption: Contents:" "INFO"
        log "" "INFO"
    } > "$source_dir/index.rst"

    # Append .rst files to the index.rst
    for rst_file in "$source_dir/"*.rst; do
        if [ -f "$rst_file" ]; then
            local rst_filename=$(basename "$rst_file" .rst)
            log "   $rst_filename" >> "$source_dir/index.rst" "INFO"
        fi
    done

    log "index.rst generated successfully in $source_dir." "INFO"
}

# Function to move generated documentation to the correct output directory
move_generated_docs() {
    local source_dir="$1"
    local destination_dir="$2"

    log "Moving generated documentation from $source_dir to $destination_dir..." "INFO"
    if [ -d "$destination_dir" ]; then
        log "Cleaning existing directory $destination_dir..." "INFO"
        sudo rm -rf "$destination_dir"/*  # Clean up the existing directory
    fi

    sudo mkdir -p "$destination_dir"
    sudo mv "$source_dir"/* "$destination_dir/"
    
    log "Moved generated docs to: $destination_dir" "INFO"
}



# Function to embed notebook into layout
embed_notebook_into_layout() {
    local output_dir=$1
    local html_file=$2
    local project_name=$3

    local basename_html_file=$(basename "$html_file")
    local original_file_path="$output_dir/$basename_html_file"
    local new_file_path="$output_dir/$project_name/$project_name.html"

    # Check if the file exists in output_dir
    if [ -f "$original_file_path" ]; then
        log "File $original_file_path exists. Proceeding with operations..." "INFO"

        # Ensure the target directory exists
        mkdir -p "$(dirname "$new_file_path")"

        # Copy the content into the new file
        cp "$original_file_path" "$new_file_path"
        log "Copied content from $original_file_path to $new_file_path" "INFO"

        # Delete the original file
        rm "$original_file_path"
        log "Deleted original file $original_file_path" "INFO"
    else
        log "File $original_file_path does not exist. No action taken." "INFO"
    fi
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
    if [ -d "$project" ] && [ "$(basename "$project")" = "datascience_adventure" ]; then
        process_project "$project"
    fi
done


log "Deployment script completed successfully!" "INFO"
