#!/bin/bash
set -e

# Ensure HLS output and log directories exist with full write permissions for Nginx worker (www-data)
mkdir -p /var/www/hls /var/log/nginx
chown -R www-data:www-data /var/www/hls /var/log/nginx 2>/dev/null || true
chmod -R 777 /var/www/hls /var/log/nginx 2>/dev/null || true

# Start Nginx in background
nginx -c /etc/nginx/nginx.conf

# Start StreamPulse Node server in foreground
exec npm run start

