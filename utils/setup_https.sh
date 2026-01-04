#!/bin/bash
set -e

echo "=================================================="
echo "   Setting up HTTPS with Certbot (Let's Encrypt)"
echo "=================================================="

# 1. Install Certbot
echo ">>> Installing Certbot..."
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx

# 2. Stop Docker Nginx temporarily (to free up port 80 for verification)
echo ">>> Stopping Docker Nginx..."
cd ~/projects/datascience_adventure
docker compose stop nginx

# 3. Obtain Certificate
echo ">>> Obtaining SSL Certificate for datascience-adventure.xyz..."
read -p "Enter your email address for Let's Encrypt registration: " EMAIL_ADDRESS

# We use --standalone because we stopped the web server
sudo certbot certonly --standalone -d datascience-adventure.xyz --non-interactive --agree-tos -m "$EMAIL_ADDRESS"

# 4. Create Nginx SSL Configuration
echo ">>> Configuring Nginx for SSL..."

# Create a new nginx config file that includes SSL
cat <<EOF > ~/projects/datascience_adventure/nginx/nginx-docker.conf
server {
    listen 80;
    server_name datascience-adventure.xyz www.datascience-adventure.xyz;
    
    # Redirect HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name datascience-adventure.xyz www.datascience-adventure.xyz;

    ssl_certificate /etc/letsencrypt/live/datascience-adventure.xyz/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/datascience-adventure.xyz/privkey.pem;
    
    # SSL Best Practices
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/htmx_website;

    # Serve static files
    location /styles/ {
        alias /var/www/htmx_website/styles/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location /templates/ {
        alias /var/www/htmx_website/templates/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location /logos/ {
        alias /var/www/htmx_website/logos/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # Proxy for Mission 7 Dashboard
    location /dashboard_mission7/ {
        proxy_pass http://homecredit_nginx:80/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Rewrite links and references for the subpath
        sub_filter_types text/html;
        sub_filter 'href="/' 'href="/dashboard_mission7/';
        sub_filter 'src="/' 'src="/dashboard_mission7/';
        sub_filter 'action="/' 'action="/dashboard_mission7/';
        sub_filter "fetch('/" "fetch('/dashboard_mission7/";
        sub_filter 'fetch("/' 'fetch("/dashboard_mission7/';
        sub_filter 'const GOOGLE_REDIRECT_URI = window.location.origin;' 'const GOOGLE_REDIRECT_URI = window.location.origin + "/dashboard_mission7";';
        sub_filter_once off;
    }

    # Handle other dynamic requests
    location / {
        try_files \$uri @flask;
    }

    # Proxy requests to Flask
    location @flask {
        proxy_pass http://app:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Fix for large files
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    # Custom 404 error page
    error_page 404 /404.html;
    location = /404.html {
        root /var/www/htmx_website;
    }
}
EOF

# 5. Update Docker Compose to mount certificates
echo ">>> Updating docker-compose.yml to mount certificates..."
# We need to mount /etc/letsencrypt into the nginx container
# This is a bit tricky with sed, so we'll append the volume config if not present
if ! grep -q "/etc/letsencrypt" ~/projects/datascience_adventure/docker-compose.yml; then
    sed -i '/volumes:/a \      - /etc/letsencrypt:/etc/letsencrypt:ro' ~/projects/datascience_adventure/docker-compose.yml
fi

# 6. Restart Docker Nginx
echo ">>> Restarting Docker Nginx..."
docker compose up -d --build nginx

echo "=================================================="
echo "   HTTPS Setup Complete!"
echo "=================================================="
