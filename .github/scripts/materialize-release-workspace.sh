#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-${PWD}/umbrella}"
SENTINEL_SOURCE="${SENTINEL_SOURCE:-${PWD}}"
MASTER_REPO_URL="${MASTER_REPO_URL:-git+https://github.com/VoidNxSEC/master.git}"

normalize_clone_url() {
  case "$1" in
    git+https://*)
      printf 'https://%s\n' "${1#git+https://}"
      ;;
    git+ssh://*)
      printf 'ssh://%s\n' "${1#git+ssh://}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

gitlink_sha() {
  local path="$1"
  git -C "$WORKSPACE_ROOT" ls-tree HEAD "$path" | awk '{print $3}'
}

repo_url() {
  case "$1" in
    adr-ledger)
      echo "${RELEASE_REPO_URL_ADR_LEDGER:-git+https://github.com/VoidNxSEC/adr-ledger.git}"
      ;;
    ai-agent-os)
      echo "${RELEASE_REPO_URL_AI_AGENT_OS:-git+https://github.com/marcosfpina/ai-agent-os.git}"
      ;;
    cerebro)
      echo "${RELEASE_REPO_URL_CEREBRO:-git+https://github.com/VoidNxSEC/cerebro.git}"
      ;;
    ml-ops-api)
      echo "${RELEASE_REPO_URL_ML_OPS_API:-git+https://github.com/VoidNxSEC/ml-ops-api.git}"
      ;;
    owasaka)
      echo "${RELEASE_REPO_URL_OWASAKA:-git+https://github.com/VoidNxSEC/O.W.A.S.A.K.A..git}"
      ;;
    phantom)
      echo "${RELEASE_REPO_URL_PHANTOM:-git+https://github.com/VoidNxSEC/phantom.git}"
      ;;
    phantom-nx)
      echo "${RELEASE_REPO_URL_PHANTOM_NX:-git+https://github.com/VoidNxSEC/phantom-nx.git}"
      ;;
    phantom-soc)
      echo "${RELEASE_REPO_URL_PHANTOM_SOC:-git+https://github.com/VoidNxSEC/phantom-soc.git}"
      ;;
    securellm-bridge)
      echo "${RELEASE_REPO_URL_SECURELLM_BRIDGE:-git+https://github.com/VoidNxSEC/securellm-bridge.git}"
      ;;
    spectre)
      echo "${RELEASE_REPO_URL_SPECTRE:-git+https://github.com/VoidNxSEC/spectre.git}"
      ;;
    spooknix)
      echo "${RELEASE_REPO_URL_SPOOKNIX:-git+https://github.com/VoidNxSEC/spooknix.git}"
      ;;
    *)
      echo "Unknown repository mapping: $1" >&2
      return 1
      ;;
  esac
}

materialize_repo() {
  local path="$1"
  local sha raw_url url

  sha="$(gitlink_sha "$path")"
  if [ -z "$sha" ]; then
    echo "Missing gitlink for $path in $(basename "$WORKSPACE_ROOT")" >&2
    return 1
  fi

  raw_url="$(repo_url "$path")"
  url="$(normalize_clone_url "$raw_url")"
  rm -rf "$WORKSPACE_ROOT/$path"
  git clone --filter=blob:none "$url" "$WORKSPACE_ROOT/$path"
  git -C "$WORKSPACE_ROOT/$path" fetch --depth 1 origin "$sha"
  git -C "$WORKSPACE_ROOT/$path" checkout "$sha"
}

rm -rf "$WORKSPACE_ROOT"
git clone --filter=blob:none "$(normalize_clone_url "$MASTER_REPO_URL")" "$WORKSPACE_ROOT"

DEFAULT_REPOS=(
  adr-ledger
  ai-agent-os
  cerebro
  ml-ops-api
  owasaka
  phantom
  phantom-nx
  phantom-soc
  securellm-bridge
  spectre
  spooknix
)

REQUESTED_RAW="${RELEASE_REPOS:-${DEFAULT_REPOS[*]}}"
REQUESTED_RAW="${REQUESTED_RAW//,/ }"

declare -a REQUESTED_REPOS=()
declare -A SEEN_REPOS=()

for path in ${REQUESTED_RAW}; do
  if [ -z "$path" ]; then
    continue
  fi
  if [ -n "${SEEN_REPOS[$path]:-}" ]; then
    continue
  fi
  SEEN_REPOS[$path]=1
  REQUESTED_REPOS+=("$path")
done

for path in "${REQUESTED_REPOS[@]}"; do
  materialize_repo "$path"
done

rm -rf "$WORKSPACE_ROOT/sentinel"
cp -a "$SENTINEL_SOURCE" "$WORKSPACE_ROOT/sentinel"

echo "Materialized release workspace at $WORKSPACE_ROOT"
find "$WORKSPACE_ROOT" -maxdepth 1 -mindepth 1 -type d | sort
