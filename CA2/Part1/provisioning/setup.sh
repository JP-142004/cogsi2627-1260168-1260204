#!/usr/bin/env bash
# CA2 Part 1 provisioning. Idempotent: safe to run more than once.
set -euo pipefail

# --- Configuration (override with environment variables) ---
REPO_URL="${REPO_URL:-https://github.com/JP-142004/cogsi2627-1260168-1260204.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
REPO_DIR="${REPO_DIR:-/home/vagrant/cogsi}"
CLONE_REPO="${CLONE_REPO:-true}"
START_APPS="${START_APPS:-false}"
GIT_TOKEN="${GIT_TOKEN:-}"

log() { echo "[setup] $*"; }

install_packages() {
  log "Installing packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    git curl unzip ca-certificates netcat-openbsd openjdk-17-jdk-headless maven
}

# Runs git as the vagrant user. The token is sent as an HTTP header for this
# command only, so it is never stored in .git/config.
git_as_vagrant() {
  if [ -n "$GIT_TOKEN" ]; then
    local auth
    auth="$(printf 'x-access-token:%s' "$GIT_TOKEN" | base64 -w0)"
    sudo -u vagrant env GIT_TERMINAL_PROMPT=0 \
      git -c "http.extraHeader=Authorization: Basic ${auth}" "$@"
  else
    sudo -u vagrant env GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

sync_repo() {
  if [ "$CLONE_REPO" != "true" ]; then
    log "CLONE_REPO=$CLONE_REPO, skipping clone"
    return
  fi
  if [ -d "$REPO_DIR/.git" ]; then
    log "Repository already cloned, updating"
    git_as_vagrant -C "$REPO_DIR" fetch origin "$REPO_BRANCH"
    git_as_vagrant -C "$REPO_DIR" checkout "$REPO_BRANCH"
    git_as_vagrant -C "$REPO_DIR" merge --ff-only "origin/$REPO_BRANCH"
  else
    log "Cloning $REPO_URL"
    git_as_vagrant clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
  fi
}

install_packages
sync_repo

log "START_APPS=$START_APPS (starting the apps is added in a later step)"
java -version
log "Done"