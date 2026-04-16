#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
NATS_CONF="$ROOT_DIR/spectre/config/nats-server.conf"

DEFAULT_SERVICES=(nats phantom-api phantom-proxy owasaka ai-agent-os)
KNOWN_NKEY_SERVICES=(owasaka ai-agent-os phantom phantom-soc cerebro securellm-bridge)

if [ "$#" -gt 0 ]; then
  SERVICES=("$@")
else
  SERVICES=("${DEFAULT_SERVICES[@]}")
fi

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [ -f "$path" ] || fail "Missing required file: $path"
}

config_pubkey() {
  local svc="$1"
  awk -v svc="$svc" '
    /# ── owasaka/ { current="owasaka" }
    /# ── ai-agent-os/ { current="ai-agent-os" }
    /# ── phantom —/ { current="phantom" }
    /# ── phantom-soc/ { current="phantom-soc" }
    /# ── cerebro/ { current="cerebro" }
    /# ── securellm-bridge/ { current="securellm-bridge" }
    /nkey: "/ {
      value=$0
      sub(/.*nkey: "/, "", value)
      sub(/".*/, "", value)
      if (current == svc) {
        print value
        exit
      }
    }
  ' "$NATS_CONF"
}

header_pubkey() {
  local nk_file="$1"
  grep -m1 '^# Public key:' "$nk_file" | sed 's/^# Public key: //'
}

wait_for_service() {
  local svc="$1"
  local cid status expected

  cid="$(docker compose ps -q "$svc")"
  [ -n "$cid" ] || fail "No container ID found for service: $svc"

  expected="running"
  case "$svc" in
    nats|phantom-api|phantom-proxy|owasaka|cerebro|securellm-bridge)
      expected="healthy"
      ;;
  esac

  for _ in $(seq 1 30); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid")"
    if [ "$status" = "$expected" ]; then
      pass "$svc is $expected"
      return 0
    fi
    sleep 2
  done

  docker compose logs --tail=80 "$svc" >&2 || true
  fail "$svc did not reach $expected"
}

echo "=== NATS Key Reload ==="
echo "Root: $ROOT_DIR"
echo

echo "=== Preflight ==="
require_file "$NATS_CONF"
require_file "$ROOT_DIR/secrets/tls/ca.crt"
require_file "$ROOT_DIR/secrets/tls/nats.crt"
require_file "$ROOT_DIR/secrets/tls/nats.key"
pass "NATS config and TLS material present"

for svc in "${KNOWN_NKEY_SERVICES[@]}"; do
  nk_file="$ROOT_DIR/spectre/config/nkeys/${svc}.nk"
  require_file "$nk_file"
  file_pub="$(header_pubkey "$nk_file")"
  conf_pub="$(config_pubkey "$svc")"
  [ -n "$file_pub" ] || fail "Public key header missing in $nk_file"
  [ -n "$conf_pub" ] || fail "Public key missing in nats-server.conf for $svc"
  [ "$file_pub" = "$conf_pub" ] || fail "Public key mismatch for $svc"
done
pass "All .nk files match nats-server.conf"

if [ -f "$ROOT_DIR/secrets/nkeys.env" ]; then
  echo "WARN  secrets/nkeys.env exists in plaintext; source of truth for runtime reload remains spectre/config/nkeys/*.nk"
fi
echo

echo "=== Recreate NATS-facing services ==="
docker compose --profile core --profile intelligence up -d --force-recreate "${SERVICES[@]}"
echo

echo "=== Wait for health ==="
for svc in "${SERVICES[@]}"; do
  wait_for_service "$svc"
done
echo

echo "=== Live checks ==="
curl -fsS http://localhost:8222/healthz >/dev/null
pass "NATS health endpoint"

if printf '%s\n' "${SERVICES[@]}" | grep -qx 'phantom-proxy'; then
  curl -fsS --cacert "$ROOT_DIR/secrets/tls/ca.crt" https://localhost:8008/health >/dev/null
  pass "Phantom TLS health endpoint"
fi
echo

echo "=== Done ==="
echo "NATS and selected clients were recreated with the current key material."
