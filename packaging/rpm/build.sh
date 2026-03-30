#!/usr/bin/env bash
# Build RPM packages for voidnxlabs services.
# Requires: fpm, rpm (rpm-build on Fedora/RHEL)
#
# Usage:
#   VERSION=0.1.0 ./packaging/rpm/build.sh
#
# Output: dist/*.rpm

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SENTINEL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$SENTINEL_ROOT}"
DIST_DIR="$SENTINEL_ROOT/dist"

if [ "$WORKSPACE_ROOT" = "$SENTINEL_ROOT" ] && [ -d "$SENTINEL_ROOT/../phantom" ]; then
  WORKSPACE_ROOT="$(cd "$SENTINEL_ROOT/.." && pwd)"
fi

mkdir -p "$DIST_DIR"

log() { echo "[rpm] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }
}

require_cmd fpm

# ── Repackage .deb artifacts as .rpm ─────────────────────────────────────────
# If .deb packages already exist (from deb/build.sh), convert them.

convert_deb_to_rpm() {
  local deb="$1"
  local rpm_path="${deb%.deb}.rpm"
  log "Converting $(basename "$deb") → RPM..."
  fpm \
    -s deb -t rpm \
    --package "$DIST_DIR/$(basename "${deb%.deb}").rpm" \
    "$deb"
  log "  -> $DIST_DIR/$(basename "${deb%.deb}").rpm"
}

if ls "$DIST_DIR"/*.deb &>/dev/null; then
  for deb in "$DIST_DIR"/*.deb; do
    convert_deb_to_rpm "$deb"
  done
else
  log "No .deb packages found in $DIST_DIR — run packaging/deb/build.sh first"
  log "Building RPMs directly from source..."

  # Fallback: build Rust binaries and wrap with fpm directly
  for project in ai-agent-os securellm-bridge phantom-nx; do
    if [ -d "$WORKSPACE_ROOT/$project" ]; then
      log "Building $project..."
      (
        cd "$WORKSPACE_ROOT/$project"
        cargo build --release 2>/dev/null || true
        bin=$(ls target/release/ | grep -v '\.' | head -1)
        if [ -n "$bin" ] && [ -f "target/release/$bin" ]; then
          fpm \
            -s dir -t rpm \
            --name "$project" \
            --version "$VERSION" \
            --maintainer "voidnxlabs <dev@voidnxlabs.io>" \
            --description "voidnxlabs $project" \
            --url "https://github.com/VoidNxSEC" \
            --license "Apache-2.0" \
            --package "$DIST_DIR/${project}_${VERSION}.rpm" \
            "target/release/$bin=/usr/bin/$bin"
        fi
      )
    fi
  done
fi

log ""
log "RPM packages built:"
ls -lh "$DIST_DIR"/*.rpm 2>/dev/null || log "  (none built)"
