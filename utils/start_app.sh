#!/bin/sh
set -e

SRC_DIR="/srv/htmx_website"
DST_DIR="/var/www/htmx_website"

mkdir -p "$DST_DIR"

if [ -d "$SRC_DIR" ]; then
    cp -a "$SRC_DIR"/. "$DST_DIR"/
fi

exec gunicorn -w 4 -b 0.0.0.0:8000 wsgi:application
