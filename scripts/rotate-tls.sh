#!/usr/bin/env bash
# rotate-tls.sh — Regenerate spectre mesh TLS certificates
#
# Usage:
#   ./sentinel/scripts/rotate-tls.sh
#
# Generates:
#   secrets/tls/ca.crt + ca.key       — self-signed CA (10 year validity)
#   secrets/tls/<service>.crt + .key   — per-service certs (1 year validity)
#
# For production: replace with Let's Encrypt (caddy auto-tls) or Vault PKI.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TLS_DIR="$ROOT/secrets/tls"

SERVICES=(nats phantom-api owasaka ai-agent-os cerebro securellm-bridge spooknix)

declare -A SERVICE_SANS
SERVICE_SANS[nats]="DNS:nats,DNS:localhost,IP:172.28.0.10,IP:127.0.0.1"
SERVICE_SANS[phantom-api]="DNS:phantom-api,DNS:localhost,IP:172.28.0.11,IP:127.0.0.1"
SERVICE_SANS[owasaka]="DNS:owasaka,DNS:localhost,IP:172.28.0.12,IP:127.0.0.1"
SERVICE_SANS[ai-agent-os]="DNS:ai-agent-os,DNS:localhost,IP:172.28.0.13,IP:127.0.0.1"
SERVICE_SANS[cerebro]="DNS:cerebro,DNS:localhost,IP:172.28.0.20,IP:127.0.0.1"
SERVICE_SANS[securellm-bridge]="DNS:securellm-bridge,DNS:localhost,IP:172.28.0.21,IP:127.0.0.1"
SERVICE_SANS[spooknix]="DNS:spooknix,DNS:localhost,IP:172.28.0.30,IP:127.0.0.1"

command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl not found"; exit 1; }

mkdir -p "$TLS_DIR"

# ── CA ────────────────────────────────────────────────────────────────────────
echo "Generating CA..."
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -days 3650 -nodes \
  -keyout "$TLS_DIR/ca.key" \
  -out "$TLS_DIR/ca.crt" \
  -subj "/O=voidnxlabs/CN=spectre-ca" 2>/dev/null

# ── Per-service certs ─────────────────────────────────────────────────────────
for SVC in "${SERVICES[@]}"; do
  SANS="${SERVICE_SANS[$SVC]}"
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$TLS_DIR/${SVC}.key" \
    -out "/tmp/${SVC}.csr" \
    -subj "/O=voidnxlabs/CN=${SVC}" 2>/dev/null

  openssl x509 -req -in "/tmp/${SVC}.csr" \
    -CA "$TLS_DIR/ca.crt" -CAkey "$TLS_DIR/ca.key" \
    -CAcreateserial -days 365 \
    -extfile <(echo "subjectAltName=${SANS}") \
    -out "$TLS_DIR/${SVC}.crt" 2>/dev/null

  rm -f "/tmp/${SVC}.csr"
  echo "  $SVC: $(openssl x509 -in "$TLS_DIR/${SVC}.crt" -noout -enddate 2>/dev/null)"
done

rm -f "$TLS_DIR/ca.srl"

echo ""
echo "TLS certs written to: $TLS_DIR/"
echo "CA valid for 10 years. Service certs valid for 1 year."
echo ""
echo "Next steps:"
echo "  1. Restart services to load new certs"
echo "  2. For production, encrypt keys: sops -e secrets/tls/<svc>.key"
echo "  3. Schedule annual rotation"
