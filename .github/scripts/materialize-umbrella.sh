#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "${ROOT_DIR}"

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

repo_url() {
  case "$1" in
    adr-ledger)
      echo "${MATERIALIZE_REPO_URL_ADR_LEDGER:-git+https://github.com/VoidNxSEC/adr-ledger.git}"
      ;;
    ai-agent-os)
      echo "${MATERIALIZE_REPO_URL_AI_AGENT_OS:-git+https://github.com/marcosfpina/ai-agent-os.git}"
      ;;
    cerebro)
      echo "${MATERIALIZE_REPO_URL_CEREBRO:-git+https://github.com/VoidNxSEC/cerebro.git}"
      ;;
    ml-ops-api)
      echo "${MATERIALIZE_REPO_URL_ML_OPS_API:-git+https://github.com/VoidNxSEC/ml-ops-api.git}"
      ;;
    neoland)
      echo "${MATERIALIZE_REPO_URL_NEOLAND:-git+https://github.com/VoidNxSEC/neoland.git}"
      ;;
    owasaka)
      echo "${MATERIALIZE_REPO_URL_OWASAKA:-git+https://github.com/VoidNxSEC/O.W.A.S.A.K.A..git}"
      ;;
    phantom)
      echo "${MATERIALIZE_REPO_URL_PHANTOM:-git+https://github.com/VoidNxSEC/phantom.git}"
      ;;
    phantom-nx)
      echo "${MATERIALIZE_REPO_URL_PHANTOM_NX:-git+https://github.com/VoidNxSEC/phantom-nx.git}"
      ;;
    phantom-soc)
      echo "${MATERIALIZE_REPO_URL_PHANTOM_SOC:-git+https://github.com/VoidNxSEC/phantom-soc.git}"
      ;;
    securellm-bridge)
      echo "${MATERIALIZE_REPO_URL_SECURELLM_BRIDGE:-git+https://github.com/VoidNxSEC/securellm-bridge.git}"
      ;;
    sentinel)
      echo "${MATERIALIZE_REPO_URL_SENTINEL:-git+https://github.com/VoidNxSEC/sentinel.git}"
      ;;
    spectre)
      echo "${MATERIALIZE_REPO_URL_SPECTRE:-git+https://github.com/VoidNxSEC/spectre.git}"
      ;;
    spooknix)
      echo "${MATERIALIZE_REPO_URL_SPOOKNIX:-git+https://github.com/VoidNxSEC/spooknix.git}"
      ;;
    *)
      echo ""
      ;;
  esac
}

clone_repo() {
  local path="$1"
  local sha
  local raw_url
  local url

  raw_url="$(repo_url "$path")"
  url="$(normalize_clone_url "$raw_url")"

  if [ -z "${url}" ]; then
    echo "missing repository mapping for ${path}" >&2
    return 1
  fi

  sha="$(git ls-tree HEAD "${path}" | awk '{print $3}')"
  if [ -z "${sha}" ]; then
    echo "missing gitlink for ${path}" >&2
    return 1
  fi

  rm -rf "${path}"
  git clone --filter=blob:none "${url}" "${path}"
  git -C "${path}" fetch --depth 1 origin "${sha}"
  git -C "${path}" checkout "${sha}"
}

DEFAULT_REPOS=(
  sentinel
  spectre
  phantom
  owasaka
  securellm-bridge
  phantom-soc
  cerebro
  adr-ledger
)

REQUESTED_RAW="${MATERIALIZE_REPOS:-${DEFAULT_REPOS[*]}}"
REQUESTED_RAW="${REQUESTED_RAW//,/ }"

declare -a REQUESTED_REPOS=()
declare -A SEEN_REPOS=()

for repo in ${REQUESTED_RAW}; do
  if [ -z "${repo}" ]; then
    continue
  fi
  if [ -n "${SEEN_REPOS[$repo]:-}" ]; then
    continue
  fi
  SEEN_REPOS[$repo]=1
  REQUESTED_REPOS+=("${repo}")
done

if [ "${MATERIALIZE_AI_AGENT_OS:-0}" = "1" ] && [ -z "${SEEN_REPOS[ai-agent-os]:-}" ]; then
  REQUESTED_REPOS+=("ai-agent-os")
fi

for repo in "${REQUESTED_REPOS[@]}"; do
  clone_repo "${repo}"
done

if [ "${#REQUESTED_REPOS[@]}" -eq 0 ]; then
  echo "no repositories requested for materialization"
fi
