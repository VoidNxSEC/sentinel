#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS  $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL  $1"
}

run_check() {
  local name="$1"
  shift
  echo ""
  echo "=== ${name} ==="
  if "$@"; then
    pass "${name}"
  else
    fail "${name}"
  fi
}

check_sops_baseline() {
  test -f "${ROOT_DIR}/.sops.yaml"
  test -f "${ROOT_DIR}/secrets/nkeys.env.enc"
  test -f "${ROOT_DIR}/sentinel/scripts/rotate-nkeys.sh"
  test -f "${ROOT_DIR}/sentinel/scripts/rotate-tls.sh"
}

check_remaining_secret_targets() {
  grep -Eq '^[[:space:]]*#?[[:space:]]*HF_TOKEN=' "${ROOT_DIR}/.env.example"
  grep -Eq '^[[:space:]]*#?[[:space:]]*DEEPSEEK_API_KEY=' "${ROOT_DIR}/.env.example"
  grep -Eq '^[[:space:]]*#?[[:space:]]*ANTHROPIC_API_KEY=' "${ROOT_DIR}/.env.example"
  grep -Eq '^[[:space:]]*#?[[:space:]]*OPENAI_API_KEY=' "${ROOT_DIR}/.env.example"
  grep -Eq 'DATABASE_URL' "${ROOT_DIR}/sentinel/docs/go-live-goals.md"
}

check_no_tracked_plaintext_secrets() {
  cd "${ROOT_DIR}"
  ! git grep -nE '^(HF_TOKEN|DATABASE_URL|DEEPSEEK_API_KEY|ANTHROPIC_API_KEY|OPENAI_API_KEY)=[^[:space:]]+' -- \
    ':!*.enc' ':!*.example' ':!**/.env' ':!**/.envrc' ':!docs/**' ':!**/*.md'
}

check_runtime_secret_bundle_present() {
  test -f "${ROOT_DIR}/secrets/runtime.env.enc" || test -f "${ROOT_DIR}/secrets/providers.env.enc"
}

echo "=== Gate 5 Secrets Checks ==="
echo "Root: ${ROOT_DIR}"

run_check "SOPS baseline" check_sops_baseline
run_check "Remaining secret targets documented" check_remaining_secret_targets
run_check "No tracked plaintext secrets" check_no_tracked_plaintext_secrets
run_check "Runtime secret bundle present" check_runtime_secret_bundle_present

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "${FAIL_COUNT}" -ne 0 ]; then
  echo "Gate 5 status: NO-GO"
  exit 1
fi

echo "Gate 5 status: PASS"
