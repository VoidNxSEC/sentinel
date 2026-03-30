#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="$ROOT_DIR/tmp/batch-5-backup"
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
NETWORK="master_spectre-net"

echo "Batch 5 Recovery check — $TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "Backing up critical configs"
tar -czf "$BACKUP_DIR/spectre-config-$TIMESTAMP.tar.gz" -C "$ROOT_DIR" spectre/config
tar -czf "$BACKUP_DIR/tls-secrets-$TIMESTAMP.tar.gz" -C "$ROOT_DIR" secrets/tls
cp "$ROOT_DIR/secrets/runtime.env.enc" "$BACKUP_DIR/runtime.env.enc.$TIMESTAMP"
cp "$ROOT_DIR/secrets/nkeys.env.enc" "$BACKUP_DIR/nkeys.env.enc.$TIMESTAMP"
ls -lh "$BACKUP_DIR"

echo "Shutting down core stack cleanly"
docker compose --profile core down --remove-orphans

CORE_SERVICES=(master-nats-1 master-phantom-api-1 master-ai-agent-os-1 master-owasaka-1 master-phantom-proxy-1)

echo "Ensuring core containers are removed"
for svc in "${CORE_SERVICES[@]}"; do
  ids=$(docker ps -aq --filter name="$svc")
  if [ -n "$ids" ]; then
    echo "  removing leftover $svc"
    docker rm -f $ids >/dev/null 2>&1 || true
  fi
done

echo "Waiting for core containers to disappear from ${NETWORK}"
for i in {1..10}; do
  if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    break
  fi
  in_use=false
  for svc in "${CORE_SERVICES[@]}"; do
    if docker network inspect "$NETWORK" --format '{{range $k,$v := .Containers}}{{println $v.Name}}{{end}}' | grep -q "$svc"; then
      in_use=true
      break
    fi
  done
  if [ "$in_use" = false ]; then
    break
  fi
  echo "  ${NETWORK} still has core containers, retrying"
  sleep 1
done

echo "Restoring service configs (no-op, leverage backups for audit)"
echo "Bringing stack back up with core profile"
docker compose --profile core up -d
echo "Installing phantom-api runtime deps (nkeys + pynacl) so NATS auth works"
docker exec master-phantom-api-1 python -m pip install --no-cache-dir nkeys==0.2.1 pynacl >/dev/null

echo "Waiting for services to settle"
sleep 10
docker compose --profile core ps

echo "Healthcheck: NATS"
curl -fsS http://localhost:8222/healthz

echo "Healthcheck: Phantom TLS proxy"
curl -fsS --cacert "$ROOT_DIR/secrets/tls/ca.crt" https://localhost:8008/health

echo "Batch 5 recovery-check concluded"
