#!/bin/bash
# Preflight checks before creating a Laravel worktree.
#
# Runs for every `grove add`. Detects setup gaps that would cause first-boot
# failures (missing Laravel hook link, missing env template, missing primary
# worktree). Setup gaps only warn, but an existing local storage/app blocks
# creation when the shared-storage hook is linked so data cannot be stranded.
#
# Set GROVE_SKIP_PREFLIGHT=true to silence warnings. Safety checks still run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/../_lib/load-config.sh"
fi
HERD_ROOT="${HERD_ROOT:-$HOME/Herd}"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/post-add.d"
TEMPLATE_ROOT="${HOME}/Development/Code/Worktree"

# Detect Laravel: look for artisan in the primary worktree. On first-ever
# worktree creation there is no primary, so we fall back to the bare repo.
primary="${HERD_ROOT}/${GROVE_REPO}-worktrees/${GROVE_REPO}"
bare_repo="${HERD_ROOT}/${GROVE_REPO}.git"

is_laravel=false
if [[ -f "${primary}/artisan" ]]; then
  is_laravel=true
elif [[ -d "$bare_repo" ]] && git -C "$bare_repo" cat-file -e HEAD:artisan 2>/dev/null; then
  is_laravel=true
fi

if [[ "$is_laravel" != "true" ]]; then
  exit 0
fi

storage_hook="${HOOKS_DIR}/${GROVE_REPO}/05-symlink-storage.sh"
bundled_storage_hook="${HOOKS_DIR}/_laravel/05-symlink-storage.sh"
storage_target="${primary}/storage/app"
if [[ -e "$bundled_storage_hook" && "$storage_hook" -ef "$bundled_storage_hook" ]] &&
   [[ -d "$storage_target" ]] && [[ ! -L "$storage_target" ]]; then
  if ! storage_entry="$(find "$storage_target" -mindepth 1 -print -quit 2>/dev/null)"; then
    echo "Error: Cannot inspect ${storage_target}; refusing to create another worktree while shared storage is enabled." >&2
    exit 1
  fi
  if [[ -n "$storage_entry" ]]; then
    echo "Error: ${storage_target} contains local files, but ${GROVE_REPO} is linked to the shared-storage hook." >&2
    echo "Move or back up those files and link storage/app safely, or remove the repo's 05-symlink-storage.sh hook and configure an external storage root in the application." >&2
    exit 1
  fi
fi

if [[ "${GROVE_SKIP_PREFLIGHT:-}" == "true" ]]; then
  exit 0
fi

warnings=()
fixes=()

# Check 1: is this repo linked to the shared _laravel hooks?
if [[ ! -L "${HOOKS_DIR}/${GROVE_REPO}/02-copy-env.sh" ]]; then
  warnings+=("Laravel hooks are not linked for ${GROVE_REPO} — SESSION_DOMAIN, VITE_APP_URL, and shared storage won't be configured.")
  fixes+=("bash ${HOOKS_DIR}/_laravel/link-repo.sh ${GROVE_REPO}")
fi

# Check 2: does the env template exist?
template_env="${TEMPLATE_ROOT}/${GROVE_REPO}/${GROVE_REPO}-env/.env"
if [[ ! -f "$template_env" ]]; then
  if [[ -f "${primary}/.env" ]]; then
    warnings+=("No env template at ${template_env} — new worktree will copy .env.example (may have stale DB name).")
    fixes+=("install -d -m 700 '$(dirname "$template_env")' && install -m 600 '${primary}/.env' '${template_env}'")
  fi
fi

# Check 3: DB_CREATE=false + no primary .env = inherit hook will fall back to .env.example.
if [[ "${DB_CREATE:-true}" != "true" && ! -f "${primary}/.env" && "${primary}" != "${GROVE_PATH}" ]]; then
  warnings+=("DB_CREATE=false but primary worktree has no .env at ${primary}/.env — new worktree's DB_DATABASE will come from .env.example.")
fi

if [[ ${#warnings[@]} -eq 0 ]]; then
  exit 0
fi

echo ""
echo "⚠  Preflight notes for ${GROVE_REPO}:"
for w in "${warnings[@]}"; do
  echo "   • $w"
done
if [[ ${#fixes[@]} -gt 0 ]]; then
  echo ""
  echo "   Fix now (one-off):"
  for f in "${fixes[@]}"; do
    echo "     $f"
  done
  echo ""
  echo "   Or run the full setup: bash ${SCRIPT_DIR%/pre-add.d}/setup-laravel-repo.sh ${GROVE_REPO}"
fi
echo ""

exit 0
