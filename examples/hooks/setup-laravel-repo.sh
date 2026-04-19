#!/bin/bash
# One-shot setup for a new Laravel repo in grove.
#
# Idempotent: safe to re-run. Prepares the repo so that `grove add <repo>`
# produces a working worktree on first boot.
#
# Steps:
#   1. Verify the repo has a bare clone at $HERD_ROOT/<repo>.git
#   2. Verify a primary worktree exists at $HERD_ROOT/<repo>-worktrees/<repo>
#   3. Link the repo to shared _laravel post-add hooks
#   4. Snapshot .env and .env.example from the primary worktree into
#      ~/Development/Code/Worktree/<repo>/<repo>-env/
#   5. Create the shared storage/app directory if missing
#
# Usage: bash ~/.grove/hooks/setup-laravel-repo.sh <repo-name>

set -e

if [[ -z "$1" ]]; then
  echo "Usage: $0 <repo-name>"
  echo ""
  echo "Example: $0 myapp"
  exit 1
fi

REPO="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/_lib/load-config.sh" ]]; then
  source "$SCRIPT_DIR/_lib/load-config.sh"
fi
HERD_ROOT="${HERD_ROOT:-$HOME/Herd}"
TEMPLATE_ROOT="${HOME}/Development/Code/Worktree"

BARE_REPO="${HERD_ROOT}/${REPO}.git"
PRIMARY="${HERD_ROOT}/${REPO}-worktrees/${REPO}"
TEMPLATE_DIR="${TEMPLATE_ROOT}/${REPO}/${REPO}-env"
STORAGE_DIR="${TEMPLATE_ROOT}/${REPO}/storage/app"

echo "Setting up grove support for: ${REPO}"
echo ""

# 1. Check bare repo
if [[ ! -d "$BARE_REPO" ]]; then
  echo "✗ No bare repo at $BARE_REPO"
  echo "  Run: grove clone <url> ${REPO}"
  exit 1
fi
echo "✓ Bare repo found: $BARE_REPO"

# 2. Check primary worktree
if [[ ! -d "$PRIMARY" ]]; then
  echo "✗ No primary worktree at $PRIMARY"
  echo "  Create one first: grove add ${REPO} <default-branch>"
  exit 1
fi

if [[ ! -f "${PRIMARY}/artisan" ]]; then
  echo "✗ Primary worktree is not a Laravel project (no artisan at ${PRIMARY})"
  exit 1
fi
echo "✓ Primary worktree is Laravel: $PRIMARY"

# 3. Link hooks
LINK_SCRIPT="${SCRIPT_DIR}/post-add.d/_laravel/link-repo.sh"
if [[ -x "$LINK_SCRIPT" ]]; then
  bash "$LINK_SCRIPT" "$REPO" >/dev/null
  echo "✓ Linked $REPO to shared _laravel post-add hooks"
else
  echo "✗ Hook linker missing: $LINK_SCRIPT"
  exit 1
fi

# 4. Snapshot .env template
mkdir -p "$TEMPLATE_DIR"
env_copied=false
if [[ -f "${PRIMARY}/.env" ]]; then
  cp "${PRIMARY}/.env" "${TEMPLATE_DIR}/.env"
  env_copied=true
fi
if [[ -f "${PRIMARY}/.env.example" ]]; then
  cp "${PRIMARY}/.env.example" "${TEMPLATE_DIR}/.env.example"
  env_copied=true
fi
if [[ "$env_copied" == "true" ]]; then
  echo "✓ Snapshotted .env + .env.example to $TEMPLATE_DIR/"
else
  echo "⚠ No .env found in primary worktree — skipped template snapshot"
fi

# 5. Shared storage/app
mkdir -p "$STORAGE_DIR"
echo "✓ Shared storage dir ready: $STORAGE_DIR"

echo ""
echo "✓ $REPO is set up. New worktrees via 'grove add $REPO <branch>' should work immediately."
