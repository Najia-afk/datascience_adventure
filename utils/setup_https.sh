#!/bin/bash
set -e

echo "=================================================="
echo "   Setting up HTTPS with Certbot (Let's Encrypt)"
echo "=================================================="

cd ~/projects/datascience_adventure

# 1. Prompt for email
read -p "Enter your email address for Let's Encrypt registration: " EMAIL_ADDRESS

# 2. Ensure containers are up (app must be built)
echo ">>> Building and starting app..."
docker compose up -d --build app

# 3. Stop nginx to free port 80
echo ">>> Stopping nginx to free port 80..."
docker compose stop nginx 2>/dev/null || true

# 4. Obtain certificate using certbot container with standalone mode
echo ">>> Obtaining SSL Certificate for datascience-adventure.xyz..."
docker compose run --rm -p 80:80 certbot \
    certbot certonly --standalone \
    -d datascience-adventure.xyz \
    --non-interactive --agree-tos -m "$EMAIL_ADDRESS" \
    --force-renewal

# 5. Start everything
echo ">>> Starting all services..."
docker compose up -d

echo "=================================================="
echo "   HTTPS Setup Complete!"
echo "   Certificate obtained and nginx is running."
echo "=================================================="
