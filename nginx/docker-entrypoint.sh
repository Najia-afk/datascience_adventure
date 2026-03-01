#!/bin/sh
# Nginx entrypoint: ensure SSL certs exist (self-signed fallback) so nginx can start.
# Certbot will replace these with real certs via webroot once nginx is serving port 80.

CERT_DIR="/etc/letsencrypt/live/datascience-adventure.xyz"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"

if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ]; then
    echo "==> SSL certs not found. Generating temporary self-signed certificate..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout "$PRIVKEY" \
        -out "$FULLCHAIN" \
        -subj "/CN=datascience-adventure.xyz" 2>/dev/null
    echo "==> Temporary self-signed cert created. Certbot will replace it."
else
    echo "==> SSL certs found. Starting nginx normally."
fi

# Execute the original CMD (nginx with reload loop)
exec "$@"
