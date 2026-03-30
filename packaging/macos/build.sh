#!/usr/bin/env bash
# Build macOS universal binaries for voidnxlabs.
# Requires: Rust targets aarch64-apple-darwin + x86_64-apple-darwin, lipo
#
# Usage:
#   VERSION=0.1.0 ./packaging/macos/build.sh
#
# Output: dist/macos/

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SENTINEL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$SENTINEL_ROOT}"
DIST_DIR="$SENTINEL_ROOT/dist/macos"

if [ "$WORKSPACE_ROOT" = "$SENTINEL_ROOT" ] && [ -d "$SENTINEL_ROOT/../phantom" ]; then
  WORKSPACE_ROOT="$(cd "$SENTINEL_ROOT/.." && pwd)"
fi

mkdir -p "$DIST_DIR"

log() { echo "[macos] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required: $1"; exit 1; }
}

require_cmd cargo
require_cmd lipo

# Add Rust targets if missing
rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true

build_universal() {
  local project="$1"
  local bin="$2"

  if [ ! -d "$WORKSPACE_ROOT/$project" ]; then
    log "Skipping $project — directory not found"
    return 0
  fi

  log "Building $project ($bin) universal binary..."
  (
    cd "$WORKSPACE_ROOT/$project"
    cargo build --release --target aarch64-apple-darwin 2>/dev/null || true
    cargo build --release --target x86_64-apple-darwin 2>/dev/null || true

    ARM="target/aarch64-apple-darwin/release/$bin"
    X86="target/x86_64-apple-darwin/release/$bin"

    if [ -f "$ARM" ] && [ -f "$X86" ]; then
      lipo -create -output "$DIST_DIR/$bin" "$ARM" "$X86"
      log "  -> $DIST_DIR/$bin (universal)"
    elif [ -f "$ARM" ]; then
      cp "$ARM" "$DIST_DIR/${bin}-arm64"
      log "  -> $DIST_DIR/${bin}-arm64 (arm64 only)"
    elif [ -f "$X86" ]; then
      cp "$X86" "$DIST_DIR/${bin}-x86_64"
      log "  -> $DIST_DIR/${bin}-x86_64 (x86_64 only)"
    else
      log "  WARN: $project build produced no binary"
    fi
  )
}

# Rust services
build_universal "ai-agent-os"       "ai-agent"
build_universal "securellm-bridge"  "securellm-bridge"
build_universal "phantom-nx"        "phantom-nx"

# Copy Homebrew formula
cp "$SENTINEL_ROOT/packaging/macos/homebrew-formula.rb" "$DIST_DIR/voidnxlabs.rb"

# Create tarball for each binary
for bin in "$DIST_DIR"/*; do
  [ -f "$bin" ] || continue
  name=$(basename "$bin")
  tar -czf "$DIST_DIR/${name}-${VERSION}-universal-apple-darwin.tar.gz" \
    -C "$DIST_DIR" "$name"
done

log ""
log "macOS artifacts:"
ls -lh "$DIST_DIR/"
