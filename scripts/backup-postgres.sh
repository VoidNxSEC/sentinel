#!/usr/bin/env bash
# backup-postgres.sh — PostgreSQL backup with retention management
#
# Usage:
#   ./scripts/backup-postgres.sh [--restore <backup_file>]
#
# Environment:
#   POSTGRES_HOST     default: localhost
#   POSTGRES_PORT     default: 5432
#   POSTGRES_USER     default: postgres
#   POSTGRES_PASSWORD default: voidnx
#   POSTGRES_DB       default: neotron
#   BACKUP_DIR        default: /var/lib/voidnxlabs/backups/postgres
#   DAILY_RETENTION   default: 7  (days)
#   WEEKLY_RETENTION  default: 4  (weeks, kept on Sunday)
#
# Backup naming:
#   daily:  neotron_daily_YYYYMMDD_HHMMSS.sql.gz
#   weekly: neotron_weekly_YYYYMMDD.sql.gz  (Sunday snapshots)
#
# Exit codes:
#   0 — success
#   1 — fatal error
#   2 — partial failure (backup created but cleanup failed)

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-voidnx}"
POSTGRES_DB="${POSTGRES_DB:-neotron}"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/voidnxlabs/backups/postgres}"
DAILY_RETENTION="${DAILY_RETENTION:-7}"
WEEKLY_RETENTION="${WEEKLY_RETENTION:-4}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[backup-pg]${NC} $*"; }
ok()    { echo -e "${GREEN}[backup-pg]${NC} $*"; }
warn()  { echo -e "${YELLOW}[backup-pg]${NC} $*"; }
error() { echo -e "${RED}[backup-pg]${NC} $*" >&2; }

export PGPASSWORD="${POSTGRES_PASSWORD}"

# ── Preflight ──────────────────────────────────────────────────────────────

for cmd in pg_dump pg_restore gzip; do
    if ! command -v "${cmd}" &>/dev/null; then
        error "Required command not found: ${cmd}"
        exit 1
    fi
done

mkdir -p "${BACKUP_DIR}/daily" "${BACKUP_DIR}/weekly"

# ── Connectivity check ─────────────────────────────────────────────────────

if ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" &>/dev/null; then
    error "PostgreSQL is not reachable at ${POSTGRES_HOST}:${POSTGRES_PORT}"
    exit 1
fi
ok "PostgreSQL is reachable"

# ── Create backup ──────────────────────────────────────────────────────────

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATESTAMP=$(date +%Y%m%d)
DOW=$(date +%u)  # 1=Monday ... 7=Sunday

DAILY_FILE="${BACKUP_DIR}/daily/neotron_daily_${TIMESTAMP}.sql.gz"

info "Starting backup of database '${POSTGRES_DB}' → ${DAILY_FILE}"
START_TIME=$(date +%s)

pg_dump \
    -h "${POSTGRES_HOST}" \
    -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    --format=plain \
    --no-owner \
    --no-privileges \
    --clean \
    --if-exists | gzip -9 > "${DAILY_FILE}"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
SIZE=$(du -sh "${DAILY_FILE}" | cut -f1)

ok "Backup complete: ${DAILY_FILE} (${SIZE}, ${ELAPSED}s)"

# ── Weekly snapshot (Sunday = DOW 7) ──────────────────────────────────────

if [[ "${DOW}" == "7" ]]; then
    WEEKLY_FILE="${BACKUP_DIR}/weekly/neotron_weekly_${DATESTAMP}.sql.gz"
    info "Sunday — creating weekly snapshot: ${WEEKLY_FILE}"
    cp "${DAILY_FILE}" "${WEEKLY_FILE}"
    ok "Weekly snapshot: ${WEEKLY_FILE}"
fi

# ── Retention cleanup ──────────────────────────────────────────────────────

CLEANUP_ERRORS=0

info "Cleaning daily backups older than ${DAILY_RETENTION} days ..."
DELETED=$(find "${BACKUP_DIR}/daily" -name "neotron_daily_*.sql.gz" \
    -mtime "+${DAILY_RETENTION}" -print -delete 2>/dev/null | wc -l) || CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
[[ "${DELETED}" -gt 0 ]] && info "Deleted ${DELETED} old daily backup(s)"

WEEKLY_CUTOFF=$(( WEEKLY_RETENTION * 7 ))
info "Cleaning weekly backups older than ${WEEKLY_RETENTION} weeks (${WEEKLY_CUTOFF} days) ..."
DELETED=$(find "${BACKUP_DIR}/weekly" -name "neotron_weekly_*.sql.gz" \
    -mtime "+${WEEKLY_CUTOFF}" -print -delete 2>/dev/null | wc -l) || CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
[[ "${DELETED}" -gt 0 ]] && info "Deleted ${DELETED} old weekly backup(s)"

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
info "Backup inventory:"
DAILY_COUNT=$(find "${BACKUP_DIR}/daily" -name "neotron_daily_*.sql.gz" | wc -l)
WEEKLY_COUNT=$(find "${BACKUP_DIR}/weekly" -name "neotron_weekly_*.sql.gz" | wc -l)
info "  Daily:  ${DAILY_COUNT} backup(s) in ${BACKUP_DIR}/daily"
info "  Weekly: ${WEEKLY_COUNT} backup(s) in ${BACKUP_DIR}/weekly"

if [[ ${CLEANUP_ERRORS} -gt 0 ]]; then
    warn "Backup created but cleanup had ${CLEANUP_ERRORS} error(s)"
    exit 2
fi

ok "All done"
