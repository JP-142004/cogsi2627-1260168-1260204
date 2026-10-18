#!/bin/bash
set -e

echo "[setup_proxy] Iniciando configuração do Nginx..."

# ========================================
# 1. Atualizar pacotes e instalar Nginx
# ========================================
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx

# ========================================
# 2. Configurar Nginx como reverse proxy para Bookstore
# ========================================
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Logs
    access_log /var/log/nginx/bookstore_access.log;
    error_log /var/log/nginx/bookstore_error.log;

    # Reverse proxy para Bookstore (app VM)
    location / {
        proxy_pass http://192.168.56.10:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF

# ========================================
# 3. Habilitar e reiniciar Nginx
# ========================================
systemctl enable nginx
systemctl restart nginx

echo "[setup_proxy] Nginx configurado e iniciado"
systemctl status nginx --no-pager

echo "[setup_proxy] Configuração concluída com sucesso!"