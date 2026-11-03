#!/bin/bash
# Copy .env.example to .env if it doesn't exist
#
# This hook creates a fresh .env file from the template.
# Repo-specific hooks can override this (e.g., to symlink instead).
#
# A repo's pre-built template (same path as _laravel/02-copy-env.sh) wins over
# .env.example. Copying it here, before 02-configure-env.sh edits APP_URL,
# stops the repo hook mistaking an edited .env.example copy for a custom .env.

ENV_TEMPLATE="$HOME/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env"
[[ -n "$GROVE_REPO" && -f "$ENV_TEMPLATE" ]] || ENV_TEMPLATE="${GROVE_PATH}/.env.example"

if [[ -f "$ENV_TEMPLATE" && ! -e "${GROVE_PATH}/.env" && ! -L "${GROVE_PATH}/.env" ]]; then
  if install -m 600 "$ENV_TEMPLATE" "${GROVE_PATH}/.env"; then
    echo "  Created .env from $ENV_TEMPLATE"
  else
    echo "  Failed to create private .env"
    exit 1
  fi
fi

exit 0
