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

# Restart or start the Flask application service
echo "Restarting Flask service..."
restart_or_start_service "htmx_website.service"

# Output status of services
echo "Checking the status of services..."
sudo systemctl status nginx
sudo systemctl status htmx_website.service

echo "Deployment complete!"
