#!/usr/bin/env bash
# init-jetstream.sh — Create JetStream streams in Spectre NATS
#
# Usage:
#   ./scripts/init-jetstream.sh [NATS_URL]
#
# Defaults:
#   NATS_URL=nats://localhost:4222
#
# Requirements:
#   nats CLI (github.com/nats-io/natscli) in PATH
#   NATS server must be running with JetStream enabled
#
# Idempotent: skips streams that already exist.

set -euo pipefail

NATS_URL="${1:-${NATS_URL:-nats://localhost:4222}}"
STREAMS_JSON="${BASH_SOURCE%/*}/../../../spectre/config/jetstream-streams.json"
STREAMS_JSON="$(realpath "${STREAMS_JSON}")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[init-js]${NC} $*"; }
ok()      { echo -e "${GREEN}[init-js]${NC} $*"; }
warn()    { echo -e "${YELLOW}[init-js]${NC} $*"; }
error()   { echo -e "${RED}[init-js]${NC} $*" >&2; }

# ── Preflight ──────────────────────────────────────────────────────────────

if ! command -v nats &>/dev/null; then
    error "nats CLI not found. Install: https://github.com/nats-io/natscli/releases"
    error "Or via nix: nix run nixpkgs#natscli -- ..."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    error "jq not found. Install: nix run nixpkgs#jq"
    exit 1
fi

if [[ ! -f "${STREAMS_JSON}" ]]; then
    error "Streams config not found: ${STREAMS_JSON}"
    exit 1
fi

# ── Wait for NATS ──────────────────────────────────────────────────────────

MAX_WAIT=30
ELAPSED=0
info "Waiting for NATS at ${NATS_URL} ..."
until nats --server "${NATS_URL}" server ping &>/dev/null; do
    if [[ ${ELAPSED} -ge ${MAX_WAIT} ]]; then
        error "NATS did not become ready within ${MAX_WAIT}s"
        exit 1
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
ok "NATS is reachable"

# ── Verify JetStream enabled ───────────────────────────────────────────────

if ! nats --server "${NATS_URL}" account info 2>/dev/null | grep -q "JetStream"; then
    error "JetStream is not enabled on this NATS server"
    error "Ensure nats-server.conf contains: jetstream { store_dir: ... }"
    exit 1
fi
ok "JetStream is enabled"

# ── Create / update streams ────────────────────────────────────────────────

STREAM_NAMES=$(jq -r '.streams[].name' "${STREAMS_JSON}")
CREATED=0
EXISTING=0
ERRORS=0

for name in ${STREAM_NAMES}; do
    STREAM_JSON=$(jq -c --arg n "${name}" '.streams[] | select(.name == $n)' "${STREAMS_JSON}")
    SUBJECTS=$(echo "${STREAM_JSON}" | jq -r '.subjects[]' | tr '\n' ',' | sed 's/,$//')
    DESCRIPTION=$(echo "${STREAM_JSON}" | jq -r '.description')
    MAX_MSGS=$(echo "${STREAM_JSON}" | jq -r '.max_msgs')
    MAX_BYTES=$(echo "${STREAM_JSON}" | jq -r '.max_bytes')
    MAX_AGE_NS=$(echo "${STREAM_JSON}" | jq -r '.max_age')
    # Convert ns to seconds for nats CLI (which takes Go duration strings)
    MAX_AGE_S=$(( MAX_AGE_NS / 1000000000 ))
    RETENTION=$(echo "${STREAM_JSON}" | jq -r '.retention')
    STORAGE=$(echo "${STREAM_JSON}" | jq -r '.storage')
    REPLICAS=$(echo "${STREAM_JSON}" | jq -r '.num_replicas')
    MAX_MSG_SIZE=$(echo "${STREAM_JSON}" | jq -r '.max_msg_size')
    DISCARD=$(echo "${STREAM_JSON}" | jq -r '.discard')

    # Check if stream already exists
    if nats --server "${NATS_URL}" stream info "${name}" &>/dev/null; then
        warn "Stream ${name} already exists — skipping (use 'nats stream edit' to update)"
        EXISTING=$((EXISTING + 1))
        continue
    fi

    info "Creating stream: ${name} (subjects: ${SUBJECTS})"
    if nats --server "${NATS_URL}" stream add "${name}" \
        --subjects "${SUBJECTS}" \
        --description "${DESCRIPTION}" \
        --retention "${RETENTION}" \
        --storage "${STORAGE}" \
        --replicas "${REPLICAS}" \
        --max-msgs "${MAX_MSGS}" \
        --max-bytes "${MAX_BYTES}" \
        --max-age "${MAX_AGE_S}s" \
        --max-msg-size "${MAX_MSG_SIZE}" \
        --discard "${DISCARD}" \
        --defaults 2>/dev/null; then
        ok "Created stream: ${name}"
        CREATED=$((CREATED + 1))
    else
        error "Failed to create stream: ${name}"
        ERRORS=$((ERRORS + 1))
    fi
done

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
info "JetStream initialization complete"
info "  Created:  ${CREATED}"
info "  Existing: ${EXISTING} (skipped)"
[[ ${ERRORS} -gt 0 ]] && error "  Errors:   ${ERRORS}" || true

if [[ ${ERRORS} -gt 0 ]]; then
    exit 1
fi

# ── List all streams ───────────────────────────────────────────────────────

echo ""
info "Current streams:"
nats --server "${NATS_URL}" stream list 2>/dev/null || true
