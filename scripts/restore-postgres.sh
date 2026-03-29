#!/usr/bin/env bash
# restore-postgres.sh — Restore PostgreSQL from a backup file
#
# Usage:
#   ./scripts/restore-postgres.sh <backup_file.sql.gz>
#
# Environment:
#   POSTGRES_HOST     default: localhost
#   POSTGRES_PORT     default: 5432
#   POSTGRES_USER     default: postgres
#   POSTGRES_PASSWORD default: voidnx
#   POSTGRES_DB       default: neotron
#   FORCE             set to "yes" to skip interactive confirmation
#
# WARNING: This will DROP and recreate the target database.
#          All existing data will be lost.

set -euo pipefail

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-voidnx}"
POSTGRES_DB="${POSTGRES_DB:-neotron}"
FORCE="${FORCE:-no}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[restore-pg]${NC} $*"; }
ok()    { echo -e "${GREEN}[restore-pg]${NC} $*"; }
warn()  { echo -e "${YELLOW}[restore-pg]${NC} $*"; }
error() { echo -e "${RED}[restore-pg]${NC} $*" >&2; }

export PGPASSWORD="${POSTGRES_PASSWORD}"

# ── Arguments ──────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    error "Usage: $0 <backup_file.sql.gz>"
    error ""
    error "Available backups:"
    BACKUP_DIR="${BACKUP_DIR:-/var/lib/voidnxlabs/backups/postgres}"
    find "${BACKUP_DIR}" -name "*.sql.gz" -printf "  %TY-%Tm-%Td %TH:%TM  %p\n" 2>/dev/null | sort -r | head -20 || true
    exit 1
fi

BACKUP_FILE="$1"

if [[ ! -f "${BACKUP_FILE}" ]]; then
    error "Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# ── Preflight ──────────────────────────────────────────────────────────────

for cmd in psql gunzip; do
    if ! command -v "${cmd}" &>/dev/null; then
        error "Required command not found: ${cmd}"
        exit 1
    fi
done

if ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" &>/dev/null; then
    error "PostgreSQL is not reachable at ${POSTGRES_HOST}:${POSTGRES_PORT}"
    exit 1
fi

# ── Confirmation ───────────────────────────────────────────────────────────

BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
BACKUP_DATE=$(stat -c %y "${BACKUP_FILE}" | cut -d'.' -f1)

echo ""
echo -e "${BOLD}${RED}⚠ WARNING: DESTRUCTIVE OPERATION${NC}"
echo ""
echo -e "  Database:    ${BOLD}${POSTGRES_DB}${NC} on ${POSTGRES_HOST}:${POSTGRES_PORT}"
echo -e "  Backup file: ${BACKUP_FILE}"
echo -e "  Backup size: ${BACKUP_SIZE}"
echo -e "  Backup date: ${BACKUP_DATE}"
echo ""
echo -e "  This will ${RED}DROP${NC} the existing database and restore from backup."
echo -e "  ${BOLD}All current data will be permanently lost.${NC}"
echo ""

if [[ "${FORCE}" != "yes" ]]; then
    read -r -p "Type 'yes' to confirm restore: " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        warn "Restore cancelled"
        exit 0
    fi
fi

# ── Terminate active connections ───────────────────────────────────────────

info "Terminating active connections to '${POSTGRES_DB}' ..."
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();" \
    &>/dev/null || warn "Could not terminate all connections (continuing)"

# ── Drop and recreate database ────────────────────────────────────────────

info "Dropping database '${POSTGRES_DB}' ..."
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
    -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
info "Creating database '${POSTGRES_DB}' ..."
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
    -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};"

# ── Restore ────────────────────────────────────────────────────────────────

info "Restoring from ${BACKUP_FILE} ..."
START_TIME=$(date +%s)

gunzip -c "${BACKUP_FILE}" | psql \
    -h "${POSTGRES_HOST}" \
    -p "${POSTGRES_PORT}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    --single-transaction \
    --no-password \
    -v ON_ERROR_STOP=1

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

ok "Restore complete in ${ELAPSED}s"

# ── Verify ────────────────────────────────────────────────────────────────

info "Verifying restored database ..."
TABLES=$(psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
ok "Restore verified: ${TABLES} table(s) in public schema"

echo ""
ok "Database '${POSTGRES_DB}' restored successfully from $(basename "${BACKUP_FILE}")"
