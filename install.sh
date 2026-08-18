#!/usr/bin/env bash
# Install or rollback the dsh-plugin-session-improvements patch for deepseek-harness.
# Usage:
#   ./install.sh <harness-root> [--check] [--build] [--test]
#   ./install.sh <harness-root> --rollback
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$SCRIPT_DIR/dsh-plugin-session-improvements.patch"
FILELIST="$SCRIPT_DIR/file-list.txt"

HARNESS_ROOT="${1:-${DSH_HARNESS_ROOT:-}}"
CHECK=0; BUILD=0; TEST=0; ROLLBACK=0
shift || true
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --build) BUILD=1 ;;
    --test)  TEST=1 ;;
    --rollback) ROLLBACK=1 ;;
    *) echo "[dsh-plugin-session-improvements] unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "$HARNESS_ROOT" ]]; then
  # walk up from cwd looking for a checkout marker
  dir="$(pwd)"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" && -d "$dir/packages/host/apiproxy" ]]; then HARNESS_ROOT="$dir"; break; fi
    dir="$(dirname "$dir")"
  done
fi
if [[ -z "$HARNESS_ROOT" || ! -d "$HARNESS_ROOT" ]]; then
  echo "[dsh-plugin-session-improvements] deepseek-harness checkout not found; pass it as the first argument" >&2
  exit 1
fi
cd "$HARNESS_ROOT"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "[dsh-plugin-session-improvements] $HARNESS_ROOT is not a git worktree" >&2; exit 1; }
echo "[dsh-plugin-session-improvements] harness root : $HARNESS_ROOT"
echo "[dsh-plugin-session-improvements] HEAD commit  : $(git rev-parse --short HEAD) (patch baseline: 47f943859b)"

if [[ $ROLLBACK -eq 1 ]]; then
  if git apply -R --check "$PATCH"; then
    echo "[dsh-plugin-session-improvements] patch reverse-applies cleanly; rolling back..."
    git apply -R "$PATCH"
    echo "[dsh-plugin-session-improvements] rolled back."
    exit 0
  fi
  echo "[dsh-plugin-session-improvements] patch does not reverse-apply cleanly; review 'git status' and restore from files/original/ manually." >&2
  exit 1
fi

if ! git apply --check "$PATCH"; then
  echo "[dsh-plugin-session-improvements] patch does NOT apply cleanly (upstream drift?). Review files/original vs files/modified and merge manually." >&2
  exit 1
fi
if [[ $CHECK -eq 1 ]]; then
  echo "[dsh-plugin-session-improvements] OK: patch applies cleanly; no changes made."
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "[dsh-plugin-session-improvements] WARNING: working tree has uncommitted changes; applying on top." >&2
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$HARNESS_ROOT/dsh-plugin-session-improvements-backup-$stamp"
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  mkdir -p "$(dirname "$backup/$f")"
  cp "$f" "$backup/$f"
done < "$FILELIST"
echo "[dsh-plugin-session-improvements] backup written : $backup"

git apply "$PATCH"
echo "[dsh-plugin-session-improvements] patch applied: $(wc -l < "$FILELIST") files."

if [[ $BUILD -eq 1 ]]; then
  echo "[dsh-plugin-session-improvements] running pnpm run build ..."
  pnpm run build
fi
if [[ $TEST -eq 1 ]]; then
  echo "[dsh-plugin-session-improvements] running affected tests ..."
  pnpm vitest run packages/session/session-persistence/tests/persistence.spec.ts
  pnpm vitest run packages/client packages/host packages/test-support
  pnpm vitest run --config vitest.web.config.ts apps/web/tests/workspace-management.e2e.ts
fi

echo
echo "[dsh-plugin-session-improvements] DONE. Restart your dsh process to activate (e.g. dsh web)."
