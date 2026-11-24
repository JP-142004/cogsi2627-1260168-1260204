#!/bin/bash
set -e

SRC="/vagrant/CA6/Part1/bookstore"
BUILD_DIR="/opt/bookstore/src"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jdk-headless netcat-openbsd rsync

# Build fora da pasta partilhada para não deixar build/ no host
mkdir -p "$BUILD_DIR"
rsync -a --delete --exclude build --exclude .gradle "$SRC/" "$BUILD_DIR/"
cd "$BUILD_DIR"
chmod +x gradlew
./gradlew :app:bootJar --no-daemon -x test
cp app/build/libs/app-*.jar /opt/bookstore/bookstore.jar

cat > /opt/bookstore/application.properties <<PROPS
spring.datasource.url=jdbc:h2:tcp://${DB_IP}:9092/bookstore;DB_CLOSE_ON_EXIT=FALSE
spring.datasource.username=sa
spring.datasource.password=
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false
PROPS

cat > /etc/systemd/system/bookstore.service <<UNIT
[Unit]
Description=Bookstore Spring Boot Application
After=network-online.target
Wants=network-online.target

[Service]
User=vagrant
ExecStartPre=/bin/bash -c 'until nc -z ${DB_IP} 9092; do sleep 2; done'
ExecStart=/usr/bin/java -jar /opt/bookstore/bookstore.jar --spring.config.additional-location=file:/opt/bookstore/
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable bookstore
systemctl restart bookstore
