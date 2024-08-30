#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to restart or start a service
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

# Function to copy updated static files and Nginx configuration
update_static_files_and_nginx() {
    echo "Copying updated static files..."
    sudo cp -r app/static/* /var/www/htmx_website/

    echo "Copying updated Nginx configuration..."
    sudo cp nginx/htmx_website /etc/nginx/sites-available/htmx_website

    if [ ! -L /etc/nginx/sites-enabled/htmx_website ]; then
        echo "Creating symbolic link for Nginx configuration..."
        sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
    fi

    echo "Refreshing Nginx configuration..."
    sudo nginx -t && sudo systemctl reload nginx
}

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
        return
    }

    move_generated_docs "$docs_dir/_build/html" "$output_dir"
}

# Function to generate a proper index.rst for Sphinx documentation
generate_index_rst() {
    local source_dir=$1

    echo ".. toctree::" > "$source_dir/index.rst"
    echo "   :maxdepth: 2" >> "$source_dir/index.rst"
    echo "   :caption: Contents:" >> "$source_dir/index.rst"
    echo "" >> "$source_dir/index.rst"

    for rst_file in "$source_dir/"*.rst; do
        rst_filename=$(basename "$rst_file" .rst)
        echo "   $rst_filename" >> "$source_dir/index.rst"
    done
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
    echo "Moved generated docs to: $destination_dir"
}

# Function to embed the notebook HTML into the corresponding layout HTML
embed_notebook_into_layout() {
    local output_dir=$1

    echo "Checking layout and notebook files in $output_dir..."

    # Loop through all layout files in the directory
    for layout_file in "$output_dir"/*_layout.html; do
        # Define the corresponding notebook file and the desired output file
        local notebook_html="${layout_file/_layout.html/.html}"  # The actual notebook HTML (e.g., Mission3.html)
        local final_html="${layout_file/_layout.html/.html}"     # The desired final output without "_layout" (e.g., mission3.html)

        # Check if the notebook file exists
        if [ -f "$notebook_html" ]; then
            echo "Embedding $notebook_html into $layout_file..."

            # Read the content of the notebook HTML
            notebook_content=$(<"$notebook_html")

            # Embed the notebook content into the layout HTML and save it as final HTML
            sed "/<div class=\"iframe-container\">/r /dev/stdin" "$layout_file" <<<"$notebook_content" > "$final_html"

            echo "Notebook successfully embedded into layout: $final_html"

            # Optionally remove the original layout file to prevent access to the unembedded layout version
            sudo rm -f "$layout_file"
        else
            echo "No matching notebook HTML found for $layout_file. Ensure the naming and paths are correct."
        fi
    done
}


# Function to place HTML files in Nginx HTML directory
place_files() {
    local source_dir=$1
    local destination_dir=$2

    echo "Copying HTML files from $source_dir to $destination_dir..."

    # Check if source and destination paths are not the same
    if [ "$source_dir" != "$destination_dir" ]; then
        # Perform the copy operation
        sudo cp -r "$source_dir"/* "$destination_dir" || {
            echo "Failed to copy files from $source_dir to $destination_dir. Check permissions."
        }
    else
        echo "Warning: Source and destination directories are the same. Skipping copy operation."
    fi
}

# Update the deploy function to handle layout embedding and ensure correct placement of files
deploy() {
    BASE_DIR=$(dirname $(realpath "$0"))
    PROJECT_DIR=$(pwd)
    NGINX_HTML_DIR="/var/www/htmx_website"
    HTML_DIR="$PROJECT_DIR/app/static"

    echo "BASE_DIR: $BASE_DIR"
    echo "PROJECT_DIR: $PROJECT_DIR"
    echo "NGINX_HTML_DIR: $NGINX_HTML_DIR"
    echo "HTML_DIR: $HTML_DIR"

    if [ ! -d "$PROJECT_DIR" ] || [ ! -d "$HTML_DIR" ]; then
        echo "Error: Project or HTML directory does not exist."
        exit 1
    fi

    update_static_files_and_nginx

    if ! command -v jupyter &> /dev/null || ! command -v sphinx-quickstart &> /dev/null; then
        echo "Error: Required commands 'jupyter' and 'Sphinx' are not installed."
        exit 1
    fi

    for html_file in "$HTML_DIR/"*.html; do
        echo "Processing HTML file: $html_file"

        if [ ! -f "$html_file" ]; then
            echo "File $html_file does not exist. Skipping..."
            continue
        fi

        colab_link=$(grep -oP 'https://colab\.research\.google\.com/github/[^"]+' "$html_file" || true)

        if [ -n "$colab_link" ]; then
            mission_name=$(echo "$colab_link" | sed -E 's#.*/(mission[^/]+)/.*#\1#')
            mission_path="$HOME/$mission_name"
            notebook_dir="$mission_path"
            scripts_dir="$mission_path/src/scripts"
            output_dir="$NGINX_HTML_DIR/$mission_name"

            echo "Processing mission: $mission_name"
            echo "Mission path: $mission_path"
            echo "Notebook directory: $notebook_dir"
            echo "Scripts directory: $scripts_dir"

            if [ -d "$mission_path" ]; then
                sudo mkdir -p "$output_dir"
                sudo chown -R ubuntu:ubuntu "$output_dir"

                convert_notebooks "$notebook_dir" "$output_dir"
                update_sphinx_docs "$scripts_dir" "$output_dir"
                embed_notebook_into_layout "$output_dir"

                # Place files correctly
                place_files "$output_dir" "$NGINX_HTML_DIR/$mission_name"
            else
                echo "Mission directory $mission_path does not exist or is not accessible. Skipping..."
            fi
        else
            echo "No Colab link found in $html_file. Skipping..."
        fi
    done

    restart_or_start_service "htmx_website.service"
    restart_or_start_service "nginx"

    echo "Deployment complete!"
}

# Execute the deployment process
deploy
