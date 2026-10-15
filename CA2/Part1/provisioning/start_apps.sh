#!/usr/bin/env bash
# CA2 Part 1: build the two apps and run them as systemd services.
# Controlled by START_APPS (default true). Idempotent.
set -euo pipefail

START_APPS="${START_APPS:-true}"
REPO_DIR="${REPO_DIR:-/home/vagrant/cogsi}"
BOOKSTORE_DIR="${BOOKSTORE_DIR:-$REPO_DIR/CA1/week2}"
CHAT_DIR="${CHAT_DIR:-$REPO_DIR/CA1/week1/build_tools/gradle_demo}"
CONFIG_DIR="${CONFIG_DIR:-/home/vagrant/config}"
DB_DIR="${DB_DIR:-/home/vagrant/h2-data}"
CHAT_PORT="${CHAT_PORT:-59001}"

log() { echo "[start_apps] $*"; }

if [ "$START_APPS" != "true" ]; then
  log "START_APPS=$START_APPS, skipping build and start"
  exit 0
fi

for d in "$BOOKSTORE_DIR" "$CHAT_DIR" "$CONFIG_DIR"; do
  if [ ! -d "$d" ]; then
    log "ERROR: $d not found (was the repository cloned and configure_db.sh run?)"
    exit 1
  fi
done

# --no-daemon: do not leave a Gradle daemon eating RAM on a 2 GB VM
build_as_vagrant() {
  sudo -u vagrant -H bash -c "cd '$1' && chmod +x gradlew && ./gradlew --no-daemon '$2'"
}

log "Building Bookstore"
build_as_vagrant "$BOOKSTORE_DIR" ":app:bootJar"
log "Building chat server"
build_as_vagrant "$CHAT_DIR" ":app:installDist"

BOOKSTORE_JAR="$(find "$BOOKSTORE_DIR/app/build/libs" -maxdepth 1 -name '*.jar' ! -name '*-plain.jar' -print -quit)"
CHAT_LIB="$CHAT_DIR/app/build/install/app/lib"
if [ -z "$BOOKSTORE_JAR" ] || [ ! -d "$CHAT_LIB" ]; then
  log "ERROR: build output not found"
  exit 1
fi

# The Bookstore must not start before the synced folder is mounted, otherwise
# H2 would silently create the database inside the VM and lose it on destroy.
cat > /etc/systemd/system/ca2-bookstore.service <<EOF
[Unit]
Description=CA2 Bookstore (Spring Boot)
After=network.target

[Service]
User=vagrant
WorkingDirectory=$BOOKSTORE_DIR
ExecStartPre=/usr/bin/mountpoint -q $DB_DIR
ExecStart=/usr/bin/java -jar $BOOKSTORE_JAR --spring.config.additional-location=file:$CONFIG_DIR/
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/ca2-chat.service <<EOF
[Unit]
Description=CA2 chat server (Gradle demo)
After=network.target

[Service]
User=vagrant
WorkingDirectory=$CHAT_DIR
ExecStart=/usr/bin/java -cp "$CHAT_LIB/*" org.example.ChatServerApp $CHAT_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ca2-bookstore ca2-chat
systemctl restart ca2-bookstore ca2-chat

wait_for_port() {
  for _ in $(seq 1 60); do
    if nc -z localhost "$1"; then
      log "$2 is listening on port $1"
      return 0
    fi
    sleep 2
  done
  log "ERROR: $2 did not open port $1"
  journalctl -u "$3" -n 30 --no-pager || true
  return 1
}

wait_for_port 8080 "Bookstore" ca2-bookstore
wait_for_port "$CHAT_PORT" "Chat server" ca2-chat
log "Done"