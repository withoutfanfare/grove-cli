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
ENV_TARGET="${GROVE_PATH}/.env"
ENV_FALLBACK="${GROVE_PATH}/.env.example"

if [[ -f "$ENV_SOURCE" ]]; then
  replace_fallback=false
  # ponytail: content equality identifies the generated fallback; add a marker
  # if identical hand-written .env files ever need different treatment.
  if [[ -f "$ENV_TARGET" && ! -L "$ENV_TARGET" && -f "$ENV_FALLBACK" ]] &&
     cmp -s "$ENV_FALLBACK" "$ENV_TARGET"; then
    replace_fallback=true
  fi

  if { [[ -e "$ENV_TARGET" ]] || [[ -L "$ENV_TARGET" ]]; } && [[ "$replace_fallback" != "true" ]]; then
    echo "  Preserved existing .env"
  elif install -m 600 "$ENV_SOURCE" "$ENV_TARGET"; then
    echo "  Copied .env from $ENV_SOURCE"
  else
    echo "  Failed to copy private .env"
    exit 1
  fi
else
  echo "  No pre-built .env at $ENV_SOURCE - keeping .env.example copy"
fi

exit 0
