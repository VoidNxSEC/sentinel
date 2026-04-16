#!/usr/bin/env bash
# rotate-nkeys.sh — Regenerate all NATS NKey credentials and encrypt with SOPS
#
# Usage:
#   ./sentinel/scripts/rotate-nkeys.sh
#
# Prerequisites:
#   - nk (nkeys CLI):    nix shell nixpkgs#nkeys
#   - sops:              nix shell nixpkgs#sops
#   - age key at:        ~/.config/sops/age/keys.txt
#
# What this does:
#   1. Generates fresh NKey user seed for each service
#   2. Writes plaintext seeds to spectre/config/nkeys/<svc>.nk (gitignored)
#   3. Updates spectre/config/nats-server.conf with new public keys
#   4. Writes secrets/nkeys.env with all seeds
#   5. Encrypts secrets/nkeys.env → secrets/nkeys.env.enc (SOPS+age)
#   6. Removes plaintext secrets/nkeys.env
#
# After running:
#   - Restart NATS: nats-server --config spectre/config/nats-server.conf --signal reload
#   - Recreate NATS-facing services so they reload the current *.nk files
#   - Commit: spectre/config/nats-server.conf + secrets/nkeys.env.enc

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NKEYS_DIR="$ROOT/spectre/config/nkeys"
NATS_CONF="$ROOT/spectre/config/nats-server.conf"
SECRETS_DIR="$ROOT/secrets"

SERVICES=(owasaka ai-agent-os phantom phantom-soc cerebro securellm-bridge)

# ── Checks ────────────────────────────────────────────────────────────────────
command -v nk   >/dev/null 2>&1 || { echo "ERROR: nk not found. Run: nix shell nixpkgs#nkeys"; exit 1; }
command -v sops >/dev/null 2>&1 || { echo "ERROR: sops not found. Run: nix shell nixpkgs#sops"; exit 1; }
[ -f "$HOME/.config/sops/age/keys.txt" ] || { echo "ERROR: age key not found at ~/.config/sops/age/keys.txt"; exit 1; }

mkdir -p "$NKEYS_DIR" "$SECRETS_DIR"

# ── Generate ──────────────────────────────────────────────────────────────────
echo "Generating NKey credentials for ${#SERVICES[@]} services..."

declare -A SEEDS PUBKEYS

for svc in "${SERVICES[@]}"; do
  seed=$(nk -gen user)
  pubkey=$(echo "$seed" | nk -inkey /dev/stdin -pubout)
  SEEDS[$svc]="$seed"
  PUBKEYS[$svc]="$pubkey"

  cat > "$NKEYS_DIR/${svc}.nk" <<EOF
# NKey seed for ${svc}
# Public key: ${pubkey}
# Rotated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT COMMIT — managed via SOPS
${seed}
EOF
  echo "  $svc: $pubkey"
done

# ── Update nats-server.conf ───────────────────────────────────────────────────
echo ""
echo "Updating NATS server config with new public keys..."

# Replace nkey lines in the config — each nkey: "U..." line
for svc in "${SERVICES[@]}"; do
  # Convert service name to match the comment pattern in nats-server.conf
  case $svc in
    owasaka)          pattern="# ── owasaka" ;;
    ai-agent-os)      pattern="# ── ai-agent-os" ;;
    phantom)          pattern="# ── phantom —" ;;
    phantom-soc)      pattern="# ── phantom-soc" ;;
    cerebro)          pattern="# ── cerebro" ;;
    securellm-bridge) pattern="# ── securellm-bridge" ;;
  esac

  # Find the line number of the service section, then replace the nkey line after it
  section_line=$(grep -n "$pattern" "$NATS_CONF" | head -1 | cut -d: -f1)
  if [ -n "$section_line" ]; then
    # The nkey: "U..." line is within 6 lines of the section comment
    end_line=$((section_line + 8))
    sed -i "${section_line},${end_line}s|nkey: \"U[A-Z0-9]*\"|nkey: \"${PUBKEYS[$svc]}\"|" "$NATS_CONF"
  fi
done

echo "  Updated: $NATS_CONF"

# ── Write secrets env ─────────────────────────────────────────────────────────
env_key() {
  echo "$1" | tr '-' '_' | tr 'a-z' 'A-Z'
}

NKEYS_ENV="$SECRETS_DIR/nkeys.env"
cat > "$NKEYS_ENV" <<EOF
# voidnxlabs — NATS NKey seeds (SOPS-encrypted)
# Rotated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Next rotation: $(date -u -d "+90 days" +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)

$(env_key owasaka)_NKEY_SEED=${SEEDS[owasaka]}
$(env_key ai-agent-os)_NKEY_SEED=${SEEDS[ai-agent-os]}
$(env_key phantom)_NKEY_SEED=${SEEDS[phantom]}
$(env_key phantom-soc)_NKEY_SEED=${SEEDS[phantom-soc]}
$(env_key cerebro)_NKEY_SEED=${SEEDS[cerebro]}
$(env_key securellm-bridge)_NKEY_SEED=${SEEDS[securellm-bridge]}
EOF

# ── Encrypt with SOPS ────────────────────────────────────────────────────────
echo ""
echo "Encrypting with SOPS..."
sops -e "$NKEYS_ENV" > "$SECRETS_DIR/nkeys.env.enc"
rm -f "$NKEYS_ENV"
echo "  Encrypted: $SECRETS_DIR/nkeys.env.enc"
echo "  Removed:   $NKEYS_ENV (plaintext)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Rotation complete. Next steps:"
echo "  1. Reload NATS:   nats-server --signal reload  (or restart container)"
echo "  2. Recreate:      nix run .#nats-reload-keys"
echo "  3. Commit:        spectre/config/nats-server.conf + secrets/nkeys.env.enc"
echo "  4. Schedule next rotation in 90 days"
