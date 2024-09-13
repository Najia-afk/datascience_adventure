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
    echo "Installing Flask and Gunicorn..."
    pip3 install Flask gunicorn
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

    echo "Configuring Nginx for SSL..."
    cat <<EOF | sudo tee /etc/nginx/sites-available/htmx_website
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Serve static files
    location /styles/ {
        alias /var/www/htmx_website/styles/;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx

    echo "Obtaining SSL certificates with Certbot..."
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

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
ExecStart=/srv/htmx_website/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8000 wsgi:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

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
    sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd

    echo "Setting up the virtual environment..."
    # Create the virtual environment if it doesn't exist
    if [ ! -d "/srv/htmx_website/venv" ]; then
        sudo mkdir -p /srv/htmx_website/venv
        sudo python3 -m venv /srv/htmx_website/venv
        echo "Virtual environment created at /srv/htmx_website/venv."
    else
        echo "Virtual environment already exists at /srv/htmx_website/venv."
    fi

    echo "Activating the virtual environment and installing dependencies..."
    sudo /srv/htmx_website/venv/bin/pip install --upgrade pip
    sudo /srv/htmx_website/venv/bin/pip install Flask gunicorn

    echo "Setting secure permissions for /srv/htmx_website..."
    sudo chown -R www-data:www-data /srv/htmx_website
    sudo chmod -R 755 /srv/htmx_website
}

# Main logic for the setup script
main() {
    check_internet_access
    check_required_files
    install_packages
    install_python_dependencies
    remove_existing_setup

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

    echo "Setup complete! Your HTMX website is now running on http://$DOMAIN or https://$DOMAIN if SSL is configured."
}

# Run the main function
main
