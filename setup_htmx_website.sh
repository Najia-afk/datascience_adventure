#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Prompt for the domain name and email address
read -p "Enter your domain name (e.g., example.com): " DOMAIN
read -p "Enter your email address for SSL certificate notifications: " EMAIL

# Update and upgrade the system
echo "Updating the system..."
sudo apt update && sudo apt upgrade -y

# Install necessary packages
echo "Installing Nginx, Python3, pip, and Certbot..."
sudo apt install -y nginx python3 python3-pip certbot python3-certbot-nginx ufw

# Install Flask
echo "Installing Flask..."
pip3 install Flask

# Remove existing setup if it exists
echo "Removing any existing setup..."
sudo systemctl stop htmx_website.service || true
sudo systemctl disable htmx_website.service || true
sudo rm -f /etc/systemd/system/htmx_website.service
sudo rm -rf /var/www/htmx_website
sudo rm -f /etc/nginx/sites-available/htmx_website
sudo rm -f /etc/nginx/sites-enabled/htmx_website
sudo nginx -t || true
sudo systemctl reload nginx || true

# Create the application directory
echo "Creating application directory..."
sudo mkdir -p /var/www/htmx_website
sudo chown -R $USER:$USER /var/www/htmx_website
cd /var/www/htmx_website

# Create a basic HTMX HTML file
echo "Creating index.html..."
cat <<EOF > /var/www/htmx_website/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HTMX Website</title>
    <script src="https://unpkg.com/htmx.org@1.9.2"></script>
</head>
<body>
    <h1>Hello from HTMX Website</h1>
    <button hx-get="/hello" hx-target="#response">Click Me</button>
    <div id="response"></div>
</body>
</html>
EOF

# Create a basic Python Flask server
echo "Creating server.py..."
cat <<EOF > /var/www/htmx_website/server.py
from flask import Flask, send_from_directory

app = Flask(__name__, static_folder='.', static_url_path='')

@app.route('/')
def index():
    return app.send_static_file('index.html')

@app.route('/hello')
def hello():
    return '<p>Hello from HTMX!</p>'

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
EOF

# Create a systemd service for the Flask application
echo "Creating systemd service file..."
cat <<EOF | sudo tee /etc/systemd/system/htmx_website.service
[Unit]
Description=HTMX Website using Flask
After=network.target

[Service]
User=www-data
WorkingDirectory=/var/www/htmx_website
ExecStart=/usr/bin/python3 /var/www/htmx_website/server.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start the Flask service
echo "Starting Flask service..."
sudo systemctl daemon-reload
sudo systemctl start htmx_website.service
sudo systemctl enable htmx_website.service

# Configure Nginx to proxy requests to the Flask application
echo "Configuring Nginx..."
cat <<EOF | sudo tee /etc/nginx/sites-available/htmx_website
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable the Nginx configuration
sudo ln -s /etc/nginx/sites-available/htmx_website /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Obtain SSL certificate using Certbot without www domain
echo "Obtaining SSL certificates with Certbot..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Set up automatic renewal of SSL certificates
echo "Setting up automatic SSL certificate renewal..."
echo "0 3 * * * /usr/bin/certbot renew --quiet" | sudo tee -a /etc/crontab > /dev/null

# Configure Firewall with custom rules
echo "Configuring the firewall..."
sudo ufw default deny incoming
sudo ufw default deny outgoing
sudo ufw limit ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw allow out http
sudo ufw allow out https
sudo ufw allow out 53
sudo ufw allow svn
sudo ufw allow git
sudo ufw logging on
sudo ufw --force enable

# Security hardening - Disable root login
echo "Disabling root login..."
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Set proper permissions
echo "Setting proper permissions for security..."
sudo chown -R www-data:www-data /var/www/htmx_website
sudo chmod -R 755 /var/www/htmx_website

echo "Setup complete! Your HTMX website is now running securely with HTTPS."
echo "Visit https://$DOMAIN to see your HTMX website!"
