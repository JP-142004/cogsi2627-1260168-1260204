#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx

cat > /etc/nginx/sites-available/default <<CONF
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://${APP_IP}:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
CONF

systemctl enable nginx
systemctl restart nginx
