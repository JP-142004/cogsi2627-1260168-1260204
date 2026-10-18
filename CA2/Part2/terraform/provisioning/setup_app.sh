#!/bin/bash
set -e

echo "[setup_app] Iniciando configuração da aplicação Bookstore..."

# ========================================
# 1. Atualizar pacotes e instalar JDK 17
# ========================================
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jdk git curl netcat-openbsd maven

# Verificar Java
java -version
javac -version

# ========================================
# 2. Clonar o repositório (como na Parte 1)
# ========================================
REPO_URL="https://github.com/JP-142004/cogsi2627-1260168-1260204.git"
REPO_PATH="/home/vagrant/cogsi"
GIT_TOKEN="${GIT_TOKEN:-}"

if [ ! -d "$REPO_PATH/.git" ]; then
  echo "[setup_app] Clonando repositório..."
  if [ -n "$GIT_TOKEN" ]; then
    TOKEN_B64=$(echo -n "x-access-token:${GIT_TOKEN}" | base64)
    git -c "http.extraHeader=Authorization: Basic ${TOKEN_B64}" clone "$REPO_URL" "$REPO_PATH"
    GIT_TERMINAL_PROMPT=0
  else
    git clone "$REPO_URL" "$REPO_PATH"
  fi
  chown -R vagrant:vagrant "$REPO_PATH"
else
  echo "[setup_app] Repositório já existe, atualizando..."
  cd "$REPO_PATH"
  git fetch origin
  git merge --ff-only origin/main || true
fi

# ========================================
# 3. Health check: esperar pela disponibilidade do H2 (192.168.56.30:9092)
# ========================================
echo "[setup_app] Aguardando disponibilidade do H2 em 192.168.56.30:9092..."
MAX_RETRIES=30
RETRY_COUNT=0

while ! nc -z 192.168.56.30 9092 2>/dev/null; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -gt $MAX_RETRIES ]; then
    echo "[setup_app] ERRO: H2 não ficou disponível após $MAX_RETRIES tentativas!"
    exit 1
  fi
  echo "[setup_app] Tentativa $RETRY_COUNT/$MAX_RETRIES - aguardando H2..."
  sleep 2
done

echo "[setup_app] H2 está disponível! Prosseguindo..."

# ========================================
# 4. Configurar application.properties para conectar ao H2 remoto
# ========================================
mkdir -p /home/vagrant/config
cat > /home/vagrant/config/application.properties <<'EOF'
# Datasource - H2 em modo servidor (TCP)
spring.datasource.url=jdbc:h2:tcp://192.168.56.30:9092/bookstore;DB_CLOSE_ON_EXIT=FALSE
spring.datasource.driver-class-name=org.h2.Driver
spring.datasource.username=sa
spring.datasource.password=

# JPA / Hibernate
spring.jpa.database-platform=org.hibernate.dialect.H2Dialect
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false

# H2 Console (opcional, para debug)
spring.h2.console.enabled=true
spring.h2.console.path=/h2-console
EOF

chown vagrant:vagrant /home/vagrant/config/application.properties

echo "[setup_app] application.properties configurado"

# ========================================
# 5. Build da Bookstore (usando Gradle wrapper)
# ========================================
echo "[setup_app] Compilando Bookstore..."
cd "$REPO_PATH/CA1/week2"

# CORRECAO: Dar permissão de execução ao gradlew (Git no Windows não preserva permissões)
chmod +x ./gradlew

./gradlew :app:bootJar --no-daemon -x test
echo "[setup_app] Build concluído"

# ========================================
# 6. Criar serviço systemd para Bookstore
# ========================================
cat > /etc/systemd/system/bookstore.service <<'EOF'
[Unit]
Description=Bookstore Spring Boot Application
After=network.target h2-server.service
Wants=network-online.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/home/vagrant/cogsi/CA1/week2
ExecStartPre=/bin/bash -c 'while ! nc -z 192.168.56.30 9092; do sleep 2; done'
ExecStart=/usr/bin/java -jar /home/vagrant/cogsi/CA1/week2/app/build/libs/app-1.0.0.jar --spring.config.additional-location=file:/home/vagrant/config/
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment="SPRING_APPLICATION_JSON={\"server.port\":8080}"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bookstore
systemctl restart bookstore

echo "[setup_app] Serviço Bookstore iniciado e habilitado"
sleep 3
systemctl status bookstore --no-pager

echo "[setup_app] Configuração concluído com sucesso!"
