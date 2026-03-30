#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TIMESTAMP="${TIMESTAMP:-$(date -u '+%Y%m%dT%H%M%SZ')}"
BACKUP_ROOT="${BACKUP_ROOT:-$ROOT_DIR/tmp/batch-5-backup}"
OUTPUT_DIR="$BACKUP_ROOT/git-config-$TIMESTAMP"
MANIFEST="$OUTPUT_DIR/manifest.tsv"

TARGET_REPOS=(
  "$ROOT_DIR"
  "$ROOT_DIR/sentinel"
  "$ROOT_DIR/spectre"
)

mkdir -p "$OUTPUT_DIR"

echo -e "repo\tpath\thead\tbranch\tremote\tbundle\tstaged_patch\tunstaged_patch\tuntracked_list" > "$MANIFEST"

for repo in "${TARGET_REPOS[@]}"; do
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Skipping $repo: not a git worktree"
    continue
  fi

  repo_name="$(basename "$repo")"
  if [ "$repo" = "$ROOT_DIR" ]; then
    repo_name="master"
  fi

  bundle_name="${repo_name}-${TIMESTAMP}.bundle"
  bundle_path="$OUTPUT_DIR/$bundle_name"
  staged_patch_name=""
  unstaged_patch_name=""
  untracked_name=""

  echo "Backing up git history for $repo_name"
  git -C "$repo" bundle create "$bundle_path" --all >/dev/null

  if ! git -C "$repo" diff --cached --quiet --ignore-submodules=dirty; then
    staged_patch_name="${repo_name}-${TIMESTAMP}.staged.patch"
    git -C "$repo" diff --cached --binary --ignore-submodules=dirty > "$OUTPUT_DIR/$staged_patch_name"
  fi

  if ! git -C "$repo" diff --quiet --ignore-submodules=dirty; then
    unstaged_patch_name="${repo_name}-${TIMESTAMP}.unstaged.patch"
    git -C "$repo" diff --binary --ignore-submodules=dirty > "$OUTPUT_DIR/$unstaged_patch_name"
  fi

  if [ -n "$(git -C "$repo" ls-files --others --exclude-standard)" ]; then
    untracked_name="${repo_name}-${TIMESTAMP}.untracked.txt"
    git -C "$repo" ls-files --others --exclude-standard > "$OUTPUT_DIR/$untracked_name"
  fi

  head_sha="$(git -C "$repo" rev-parse HEAD)"
  branch_name="$(git -C "$repo" branch --show-current || true)"
  remote_url="$(
    git -C "$repo" remote get-url github 2>/dev/null ||
    git -C "$repo" remote get-url origin 2>/dev/null ||
    true
  )"

  echo -e "${repo_name}\t${repo}\t${head_sha}\t${branch_name}\t${remote_url}\t${bundle_name}\t${staged_patch_name}\t${unstaged_patch_name}\t${untracked_name}" >> "$MANIFEST"
done

echo "Git config backup written to $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
