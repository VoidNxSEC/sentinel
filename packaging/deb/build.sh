#!/usr/bin/env bash
# Build Debian packages for voidnxlabs services.
# Requires: cargo-deb (Rust), fpm (Ruby gem), cross (Rust cross-compiler)
#
# Usage:
#   VERSION=0.1.0 ./packaging/deb/build.sh
#
# Output: dist/*.deb

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SENTINEL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$SENTINEL_ROOT}"
DIST_DIR="$SENTINEL_ROOT/dist"

if [ "$WORKSPACE_ROOT" = "$SENTINEL_ROOT" ] && [ -d "$SENTINEL_ROOT/../phantom" ]; then
  WORKSPACE_ROOT="$(cd "$SENTINEL_ROOT/.." && pwd)"
fi

mkdir -p "$DIST_DIR"

log() { echo "[deb] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }
}

require_cmd cargo
require_cmd fpm

# ── Rust binaries (cargo-deb) ─────────────────────────────────────────────────

build_rust_deb() {
  local project="$1"
  local bin="$2"
  log "Building $project ($bin) .deb..."

  if [ ! -d "$WORKSPACE_ROOT/$project" ]; then
    log "  Skipping $project — directory not found"
    return 0
  fi

  (
    cd "$WORKSPACE_ROOT/$project"
    if cargo deb \
      --no-build \
      --output "$DIST_DIR/${bin}_${VERSION}_${ARCH}.deb" \
      2>/dev/null
    then
      :
    else
      cargo build --release
      fpm \
        -s dir -t deb \
        --name "$bin" \
        --version "$VERSION" \
        --architecture "$ARCH" \
        --maintainer "voidnxlabs <dev@voidnxlabs.io>" \
        --description "voidnxlabs $project" \
        --url "https://github.com/VoidNxSEC" \
        --license "Apache-2.0" \
        --prefix /usr/bin \
        --package "$DIST_DIR/${bin}_${VERSION}_${ARCH}.deb" \
        "target/release/$bin=/usr/bin/$bin"
    fi
  )
  log "  -> $DIST_DIR/${bin}_${VERSION}_${ARCH}.deb"
}

# ── Python services (fpm wrapping virtualenv) ─────────────────────────────────

build_python_deb() {
  local project="$1"
  local service_name="$2"
  local entrypoint="$3"
  log "Building $project Python .deb..."

  if [ ! -d "$WORKSPACE_ROOT/$project" ]; then
    log "  Skipping $project — directory not found"
    return 0
  fi

  local staging="$DIST_DIR/staging/$service_name"
  rm -rf "$staging"
  mkdir -p "$staging/opt/$service_name"

  (
    cd "$WORKSPACE_ROOT/$project"
    python3 -m venv "$staging/opt/$service_name/venv"
    "$staging/opt/$service_name/venv/bin/pip" install -q --upgrade pip
    "$staging/opt/$service_name/venv/bin/pip" install -q .
  )

  # Systemd unit
  mkdir -p "$staging/lib/systemd/system"
  cat > "$staging/lib/systemd/system/${service_name}.service" <<UNIT
[Unit]
Description=voidnxlabs $project
After=network.target nats.service
Requires=nats.service

[Service]
Type=simple
User=voidnxlabs
ExecStart=/opt/$service_name/venv/bin/$entrypoint
Restart=on-failure
RestartSec=5s
EnvironmentFile=-/etc/voidnxlabs/env

[Install]
WantedBy=multi-user.target
UNIT

  fpm \
    -s dir -t deb \
    --name "$service_name" \
    --version "$VERSION" \
    --architecture all \
    --maintainer "voidnxlabs <dev@voidnxlabs.io>" \
    --description "voidnxlabs $project" \
    --url "https://github.com/VoidNxSEC" \
    --license "Apache-2.0" \
    --after-install "$SENTINEL_ROOT/packaging/deb/postinst.sh" \
    --package "$DIST_DIR/${service_name}_${VERSION}_all.deb" \
    -C "$staging" \
    opt lib

  log "  -> $DIST_DIR/${service_name}_${VERSION}_all.deb"
}

# ── Build all services ────────────────────────────────────────────────────────

# Rust binaries
build_rust_deb "ai-agent-os"        "ai-agent"
build_rust_deb "securellm-bridge"   "securellm-bridge"
build_rust_deb "phantom-nx"         "phantom-nx"

# Go binary (cross-compile to produce Linux binary, then wrap with fpm)
if [ -d "$WORKSPACE_ROOT/owasaka" ]; then
  log "Building owasaka (Go) .deb..."
  (
    cd "$WORKSPACE_ROOT/owasaka"
    GOOS=linux GOARCH=amd64 go build -o "$DIST_DIR/owasaka" ./cmd/owasaka/... 2>/dev/null || \
    GOOS=linux GOARCH=amd64 go build -o "$DIST_DIR/owasaka" ./... || true
  )
  if [ -f "$DIST_DIR/owasaka" ]; then
    fpm \
      -s dir -t deb \
      --name "owasaka" \
      --version "$VERSION" \
      --architecture "$ARCH" \
      --maintainer "voidnxlabs <dev@voidnxlabs.io>" \
      --description "voidnxlabs owasaka network SIEM" \
      --url "https://github.com/VoidNxSEC" \
      --license "Apache-2.0" \
      --package "$DIST_DIR/owasaka_${VERSION}_${ARCH}.deb" \
      "$DIST_DIR/owasaka=/usr/bin/owasaka"
    log "  -> $DIST_DIR/owasaka_${VERSION}_${ARCH}.deb"
  fi
fi

# Python services
build_python_deb "phantom"  "phantom-api"  "phantom-api"
build_python_deb "cerebro"  "cerebro"      "cerebro"
build_python_deb "spooknix" "spooknix"     "spooknix"

log ""
log "Debian packages built:"
ls -lh "$DIST_DIR"/*.deb 2>/dev/null || log "  (none built)"
