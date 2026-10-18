#!/bin/bash
set -e

echo "[setup_db] Iniciando configuração do servidor H2..."

# ========================================
# 1. Atualizar pacotes e instalar JDK 17
# ========================================
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jre-headless

# Verificar Java
java -version

# ========================================
# 2. Criar diretório para o H2 e dados
# ========================================
mkdir -p /var/lib/h2
mkdir -p /opt/h2
chown -R vagrant:vagrant /var/lib/h2

# ========================================
# 3. Descarregar H2 (versão 2.2.224, compatível com Spring Boot 3.3.0)
# ========================================
H2_VERSION="2.2.224"
H2_JAR="/opt/h2/h2-${H2_VERSION}.jar"

if [ ! -f "$H2_JAR" ]; then
  echo "[setup_db] Descarregando H2 ${H2_VERSION}..."
  wget -q "https://repo1.maven.org/maven2/com/h2database/h2/${H2_VERSION}/h2-${H2_VERSION}.jar" -O "$H2_JAR"
  chmod 644 "$H2_JAR"
fi

echo "[setup_db] H2 instalado em: $H2_JAR"

# ========================================
# 4. Criar serviço systemd para H2
# ========================================
cat > /etc/systemd/system/h2-server.service <<'EOF'
[Unit]
Description=H2 Database Server (TCP)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/var/lib/h2
ExecStart=/usr/bin/java -cp /opt/h2/h2-2.2.224.jar org.h2.tools.Server -tcp -tcpAllowOthers -tcpPort 9092 -baseDir /var/lib/h2 -ifNotExists
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable h2-server
systemctl restart h2-server

echo "[setup_db] Serviço H2 iniciado e habilitado"

# ========================================
# 5. Configurar firewall (ufw)
# ========================================
apt-get install -y ufw

# Regras de firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp                                    # SSH (necessário para Vagrant)
ufw allow from 192.168.56.10 to any port 9092 proto tcp  # Permite apenas app

ufw --force enable

echo "[setup_db] Firewall configurado"
ufw status verbose

echo "[setup_db] Configuração concluída com sucesso!"