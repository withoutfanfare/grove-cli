#!/bin/bash
# Copy pre-built .env template for this repo
#
# This runs AFTER the global 01-copy-env.sh hook, so it will
# replace the copied .env.example with the pre-built template.
#
# Each worktree gets its own COPY of the .env, allowing:
#   - Independent APP_URL per worktree
#   - Independent DB_DATABASE per worktree
#   - Multiple worktrees running simultaneously
#
# The template .env should have placeholder values that get
# updated by 03-configure-env.sh (APP_URL, DB_DATABASE).
#
# Expected path: ~/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env

ENV_SOURCE="$HOME/Development/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env"

if [[ -f "$ENV_SOURCE" ]]; then
  # Remove the .env created by the global hook (or any existing symlink)
  rm -f "${GROVE_PATH}/.env"

  # Copy the pre-built .env template
  cp "$ENV_SOURCE" "${GROVE_PATH}/.env"
  echo "  Copied .env from $ENV_SOURCE"
else
  echo "  No pre-built .env at $ENV_SOURCE - keeping .env.example copy"
fi

exit 0
