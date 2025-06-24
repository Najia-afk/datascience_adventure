#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check for internet access
check_internet_access() {
    echo "Checking for internet access..."
    if ! ping -c 1 google.com &> /dev/null; then
        echo "No internet access detected. Please ensure your server is connected to the internet and try again."
        exit 1
    fi
}

# Check for required files and directories
check_required_files() {
    echo "Checking required files and directories..."

    # Check if the application directory exists
    if [ ! -d "app" ]; then
        echo "Error: The 'app' directory does not exist. Please ensure your application files are present in the 'app' directory."
        exit 1
    fi

    # Check if the nginx configuration file exists
    if [ ! -f "nginx/htmx_website" ]; then
        echo "Error: Nginx configuration file 'nginx/htmx_website' not found. Please ensure the file is available."
        exit 1
    fi

    echo "Required files and directories are present."
}

# Prompt for the domain name and setup option
read -p "Enter your domain name (e.g., example.com): " DOMAIN
read -p "Enter 'SSL' for full setup with SSL, 'SSL Only' to only configure SSL, or press Enter for no SSL: " OPTION

# Function to install required packages
install_packages() {
    echo "Installing Nginx, Python3, pip, Gunicorn, and Certbot..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y nginx python3 python3-pip certbot python3-certbot-nginx ufw python3-venv
}

# Function to install Python dependencies
install_python_dependencies() {
    echo "Installing Flask and Gunicorn in a virtual environment..."
    # Ensure python3-venv is installed
    sudo apt-get update
    sudo apt-get install -y python3-venv

    # Create the virtual environment if it doesn't exist
    if [ ! -d "/srv/htmx_website/venv" ]; then
        sudo mkdir -p /srv/htmx_website
        sudo python3 -m venv /srv/htmx_website/venv
        sudo chown -R www-data:www-data /srv/htmx_website/venv
        echo "Virtual environment created at /srv/htmx_website/venv."
    else
        echo "Virtual environment already exists at /srv/htmx_website/venv."
    fi

    # Ensure pip is available in the venv
    if [ ! -x "/srv/htmx_website/venv/bin/pip" ]; then
        echo "pip not found in venv, attempting to bootstrap pip with get-pip.py..."
        curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
        sudo /srv/htmx_website/venv/bin/python3 /tmp/get-pip.py
        sudo chown www-data:www-data /srv/htmx_website/venv/bin/pip
        rm /tmp/get-pip.py
    fi

    # Install latest Flask and Gunicorn in the venv
    sudo -u www-data /srv/htmx_website/venv/bin/pip install --upgrade pip
    sudo -u www-data /srv/htmx_website/venv/bin/pip install Flask gunicorn
    
    # Ensure gunicorn is executable
    if [ -f "/srv/htmx_website/venv/bin/gunicorn" ]; then
        sudo chmod +x /srv/htmx_website/venv/bin/gunicorn
        echo "Gunicorn executable permissions set."
    else
        echo "Warning: Gunicorn executable not found after installation!"
        echo "Attempting to install gunicorn again..."
        sudo -u www-data /srv/htmx_website/venv/bin/pip install --force-reinstall gunicorn
        if [ -f "/srv/htmx_website/venv/bin/gunicorn" ]; then
            sudo chmod +x /srv/htmx_website/venv/bin/gunicorn
            echo "Gunicorn executable permissions set after reinstall."
        else
            echo "ERROR: Failed to install gunicorn. Check your Python environment."
            exit 1
        fi
    fi
}

# Function to remove existing setup if it exists
remove_existing_setup() {
    echo "Removing any existing setup..."
    sudo systemctl stop htmx_website.service || true
    sudo systemctl disable htmx_website.service || true
    sudo rm -f /etc/systemd/system/htmx_website.service
    sudo rm -rf /srv/htmx_website
    sudo rm -f /etc/nginx/sites-available/htmx_website
    sudo rm -f /etc/nginx/sites-enabled/htmx_website
    sudo nginx -t || true
    sudo systemctl reload nginx || true
}

# Function to configure SSL with Nginx
configure_nginx_ssl() {
    read -p "Enter your email address for SSL certificate notifications: " EMAIL

    echo "Copying Nginx config from nginx/htmx_website..."
    sudo cp nginx/htmx_website /etc/nginx/sites-available/htmx_website
    sudo ln -sf /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/htmx_website

    echo "Testing Nginx configuration..."
    sudo nginx -t
    sudo systemctl reload nginx

    echo "Obtaining SSL certificates with Certbot..."
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

    echo "Reloading Nginx with SSL certificates..."
    sudo nginx -t
    sudo systemctl reload nginx

    echo "Setting up automatic SSL certificate renewal..."
    echo "0 3 * * * /usr/bin/certbot renew --quiet" | sudo tee -a /etc/crontab > /dev/null

    echo "SSL setup complete! Visit https://$DOMAIN to see your HTMX website!"
}

# Function to configure Nginx without SSL
configure_nginx() {
    echo "Configuring Nginx..."
    sudo cp nginx/htmx_website /etc/nginx/sites-available/htmx_website

    sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx
}

# Function to set up the Flask application
setup_flask_app() {
    echo "Setting up the Flask application in /srv/htmx_website..."
    sudo mkdir -p /srv/htmx_website
    sudo cp -r app/* /srv/htmx_website/
    sudo chown -R www-data:www-data /srv/htmx_website
    sudo find /srv/htmx_website -type d -exec chmod 755 {} \;  # Set directories to 755
    sudo find /srv/htmx_website -type f -exec chmod 644 {} \;  # Set files to 644
}

# Function to create the Gunicorn systemd service
create_gunicorn_service() {
    echo "Creating systemd service file for Gunicorn..."
    cat <<EOF | sudo tee /etc/systemd/system/htmx_website.service
[Unit]
Description=HTMX Website using Gunicorn and Flask
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/srv/htmx_website
ExecStart=/srv/htmx_website/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8000 wsgi:application
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Verify gunicorn exists before starting service
    if [ ! -f "/srv/htmx_website/venv/bin/gunicorn" ]; then
        echo "Warning: Gunicorn executable not found. Reinstalling..."
        sudo -u www-data /srv/htmx_website/venv/bin/pip install --force-reinstall gunicorn
        sudo chmod +x /srv/htmx_website/venv/bin/gunicorn
    fi

    sudo systemctl daemon-reload
    sudo systemctl start htmx_website.service
    sudo systemctl enable htmx_website.service
}

# Function to configure the firewall and harden the system
configure_firewall_and_security() {
    echo "Configuring the firewall..."
    sudo ufw enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow 'Nginx Full'
    sudo ufw allow 53
    sudo ufw allow 443/tcp

    sudo ufw reload
    sudo ufw status

    echo "Disabling root login for SSH..."
    # Use correct service name for Ubuntu (usually 'ssh', not 'sshd')
    sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    if systemctl list-units --type=service | grep -q '^ssh\.service'; then
        sudo systemctl restart ssh
    elif systemctl list-units --type=service | grep -q '^sshd\.service'; then
        sudo systemctl restart sshd
    else
        echo "Warning: SSH service not found to restart. Please restart SSH manually if needed."
    fi

    echo "Setting secure permissions for /srv/htmx_website..."
    sudo chown -R www-data:www-data /srv/htmx_website
    sudo chmod -R 755 /srv/htmx_website
    
    # Make sure gunicorn is executable (with safe check)
    if [ -f "/srv/htmx_website/venv/bin/gunicorn" ]; then
        sudo chmod +x /srv/htmx_website/venv/bin/gunicorn
        echo "Ensured gunicorn is executable."
    else
        echo "Warning: Gunicorn executable not found at expected location."
        echo "This may indicate an installation problem with the virtual environment."
    fi
}

# Main logic for the setup script
main() {
    check_internet_access
    check_required_files
    install_packages
    remove_existing_setup
    install_python_dependencies  # Install dependencies after removing existing setup
    
    if [[ "$OPTION" == "SSL Only" ]]; then
        configure_nginx_ssl
        exit 0
    fi

    setup_flask_app
    create_gunicorn_service

    if [[ "$OPTION" == "SSL" ]]; then
        configure_nginx_ssl
    else
        configure_nginx
    fi

    configure_firewall_and_security

    # Final verification that gunicorn is executable
    if [ -f "/srv/htmx_website/venv/bin/gunicorn" ]; then
        sudo chmod +x /srv/htmx_website/venv/bin/gunicorn
    else
        echo "ERROR: Gunicorn executable still not found after setup!"
        echo "Check the Flask application setup and Python environment."
    fi

    echo "Setup complete! Your HTMX website is now running on http://$DOMAIN or https://$DOMAIN if SSL is configured."
}

# Run the main function
main