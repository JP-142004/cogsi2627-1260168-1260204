#!/bin/bash
set -e

H2_VERSION="2.2.224"
H2_JAR="/opt/h2/h2-${H2_VERSION}.jar"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jre-headless ufw wget

mkdir -p /opt/h2 /var/lib/h2
chown vagrant:vagrant /var/lib/h2

if [ ! -f "$H2_JAR" ]; then
  wget -q "https://repo1.maven.org/maven2/com/h2database/h2/${H2_VERSION}/h2-${H2_VERSION}.jar" -O "$H2_JAR"
fi

cat > /etc/systemd/system/h2-server.service <<UNIT
[Unit]
Description=H2 Database Server (TCP)
After=network.target

[Service]
User=vagrant
WorkingDirectory=/var/lib/h2
ExecStart=/usr/bin/java -cp ${H2_JAR} org.h2.tools.Server -tcp -tcpAllowOthers -tcpPort 9092 -baseDir /var/lib/h2 -ifNotExists
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now h2-server

# Só a app acede ao H2
ufw default deny incoming
ufw allow 22/tcp
ufw allow from "$APP_IP" to any port 9092 proto tcp
ufw --force enable
