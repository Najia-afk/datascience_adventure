#!/bin/sh
set -e

SRC_DIR="/srv/htmx_website"
DST_DIR="/var/www/htmx_website"
STATIC_SRC="$SRC_DIR/static"

mkdir -p "$DST_DIR"

# Sync the full /srv tree into the nginx volume
if [ -d "$SRC_DIR" ]; then
    cp -a "$SRC_DIR"/. "$DST_DIR"/
fi

# Also copy static assets to the ROOT of nginx dir
# (nginx expects /var/www/htmx_website/styles/, not .../static/styles/)
if [ -d "$STATIC_SRC" ]; then
    for sub in templates styles logos images articles; do
        if [ -d "$STATIC_SRC/$sub" ]; then
            mkdir -p "$DST_DIR/$sub"
            cp -a "$STATIC_SRC/$sub"/. "$DST_DIR/$sub"/
        fi
    done
    # Top-level HTML files (index.html, 404.html, mission_layout.html)
    for f in "$STATIC_SRC"/*.html; do
        [ -f "$f" ] && cp -a "$f" "$DST_DIR/"
    done
fi

exec gunicorn -w 4 -b 0.0.0.0:8000 wsgi:application
