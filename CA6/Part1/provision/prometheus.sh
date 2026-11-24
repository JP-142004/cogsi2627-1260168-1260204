#!/bin/bash
set -e

PROMETHEUS_VERSION="2.53.2"
CONFIG_SRC="/vagrant/CA6/Part1/monitoring/prometheus/prometheus.yml"

if ! /usr/local/bin/prometheus --version 2>&1 | grep -q "version ${PROMETHEUS_VERSION}"; then
  cd /tmp
  wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
  tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
  install -m 0755 "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/
  rm -rf prometheus-*
fi

id prometheus >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /var/lib/prometheus

# A config vive no repositório; o symlink faz com que um git pull + reload baste
ln -sf "$CONFIG_SRC" /etc/prometheus/prometheus.yml
promtool check config /etc/prometheus/prometheus.yml

cat > /etc/systemd/system/prometheus.service <<UNIT
[Unit]
Description=Prometheus
After=network-online.target vagrant.mount
Wants=network-online.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.enable-lifecycle
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus
