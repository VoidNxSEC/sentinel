#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SENTINEL_ROOT="${SENTINEL_ROOT:-$(cd -- "${SCRIPT_DIR}/../.." && pwd)}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${SENTINEL_ROOT}/.workspace}"
LOCK_FILE="${LOCK_FILE:-${SENTINEL_ROOT}/flake.lock}"
PYTHON_BIN="${PYTHON_BIN:-}"

if [ -z "$PYTHON_BIN" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "Missing required command: python3 or python" >&2
    exit 1
  fi
fi

DEFAULT_REPOS=(
  adr-ledger
  phantom
  cerebro
  spectre
  owasaka
  securellm-bridge
  ai-agent-os
  phantom-soc
  spooknix
  phantom-nx
  ml-ops-api
)

normalize_clone_url() {
  case "$1" in
    git+https://*)
      printf 'https://%s\n' "${1#git+https://}"
      ;;
    git+ssh://git@github.com/*)
      printf 'https://github.com/%s\n' "${1#git+ssh://git@github.com/}"
      ;;
    ssh://git@github.com/*)
      printf 'https://github.com/%s\n' "${1#ssh://git@github.com/}"
      ;;
    git@github.com:*)
      printf 'https://github.com/%s\n' "${1#git@github.com:}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

repo_default_url() {
  case "$1" in
    adr-ledger) echo "git+https://github.com/VoidNxSEC/adr-ledger.git" ;;
    ai-agent-os) echo "git+https://github.com/marcosfpina/ai-agent-os.git" ;;
    cerebro) echo "git+https://github.com/VoidNxSEC/cerebro.git" ;;
    ml-ops-api) echo "git+https://github.com/VoidNxSEC/ml-ops-api.git" ;;
    owasaka) echo "git+https://github.com/VoidNxSEC/O.W.A.S.A.K.A..git" ;;
    phantom) echo "git+https://github.com/VoidNxSEC/phantom.git" ;;
    phantom-nx) echo "git+https://github.com/VoidNxSEC/phantom-nx.git" ;;
    phantom-soc) echo "git+https://github.com/VoidNxSEC/phantom-soc.git" ;;
    securellm-bridge) echo "git+https://github.com/VoidNxSEC/securellm-bridge.git" ;;
    spectre) echo "git+https://github.com/VoidNxSEC/spectre.git" ;;
    spooknix) echo "git+https://github.com/VoidNxSEC/spooknix.git" ;;
    *)
      echo "Unknown repository mapping: $1" >&2
      return 1
      ;;
  esac
}

repo_default_ref() {
  echo "main"
}

lock_value() {
  local node="$1"
  local key="$2"
  "$PYTHON_BIN" - "$LOCK_FILE" "$node" "$key" <<'PY'
import json
import pathlib
import sys

lock_file = pathlib.Path(sys.argv[1])
node = sys.argv[2]
key = sys.argv[3]

if not lock_file.exists():
    raise SystemExit(0)

with lock_file.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

value = ((data.get("nodes", {}).get(node, {}) or {}).get("locked", {}) or {}).get(key)
if isinstance(value, str):
    print(value)
PY
}

repo_env_key() {
  echo "$1" | tr '[:lower:]-' '[:upper:]_'
}

resolve_repo_url() {
  local repo="$1"
  local env_key lock_url
  env_key="$(repo_env_key "$repo")"

  local override_var="SENTINEL_REPO_URL_${env_key}"
  if [ -n "${!override_var:-}" ]; then
    echo "${!override_var}"
    return 0
  fi

  lock_url="$(lock_value "$repo" "url" || true)"
  if [ -n "$lock_url" ]; then
    echo "$lock_url"
    return 0
  fi

  repo_default_url "$repo"
}

resolve_repo_ref() {
  local repo="$1"
  local env_key lock_ref
  env_key="$(repo_env_key "$repo")"

  local override_var="SENTINEL_REPO_REF_${env_key}"
  if [ -n "${!override_var:-}" ]; then
    echo "${!override_var}"
    return 0
  fi

  lock_ref="$(lock_value "$repo" "rev" || true)"
  if [ -n "$lock_ref" ]; then
    echo "$lock_ref"
    return 0
  fi

  repo_default_ref "$repo"
}

checkout_ref() {
  local repo_dir="$1"
  local ref="$2"

  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    git -C "$repo_dir" fetch --depth 1 origin "$ref"
    git -C "$repo_dir" checkout --detach "$ref"
    return 0
  fi

  git -C "$repo_dir" fetch --depth 1 origin "$ref" || true
  if git -C "$repo_dir" rev-parse --verify "origin/$ref" >/dev/null 2>&1; then
    git -C "$repo_dir" checkout -B "$ref" "origin/$ref"
  else
    git -C "$repo_dir" checkout "$ref"
  fi
}

materialize_repo() {
  local repo="$1"
  local repo_dir="$WORKSPACE_ROOT/$repo"
  local raw_url clone_url ref

  raw_url="$(resolve_repo_url "$repo")"
  clone_url="$(normalize_clone_url "$raw_url")"
  ref="$(resolve_repo_ref "$repo")"

  rm -rf "$repo_dir"
  git clone --filter=blob:none "$clone_url" "$repo_dir"
  checkout_ref "$repo_dir" "$ref"
  echo "materialized $repo @ $(git -C "$repo_dir" rev-parse HEAD)"
}

REQUESTED_RAW="${SENTINEL_REPOS:-${DEFAULT_REPOS[*]}}"
REQUESTED_RAW="${REQUESTED_RAW//,/ }"

declare -a REQUESTED_REPOS=()
declare -A SEEN=()

for repo in ${REQUESTED_RAW}; do
  [ -n "$repo" ] || continue
  if [ -n "${SEEN[$repo]:-}" ]; then
    continue
  fi
  SEEN[$repo]=1
  REQUESTED_REPOS+=("$repo")
done

mkdir -p "$WORKSPACE_ROOT"

for repo in "${REQUESTED_REPOS[@]}"; do
  materialize_repo "$repo"
done

echo "workspace ready at $WORKSPACE_ROOT"
