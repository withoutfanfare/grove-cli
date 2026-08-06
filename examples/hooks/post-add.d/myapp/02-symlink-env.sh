#!/bin/bash
# Symlink to a pre-built .env file for this specific repo
#
# Numbered 02- so it runs after the global 01-copy-env.sh and
# 02-configure-env.sh hooks in the merged sequence, replacing the
# copied .env.example with a symlink to your pre-configured .env.
#
# Benefits:
#   - All worktrees share the same .env (secrets, API keys, etc.)
#   - Update once, applies everywhere
#   - No need to manually configure each worktree
#
# Setup:
#   1. Create a directory for your pre-built env files:
#      mkdir -p ~/Code/Worktree/myapp/myapp-env
#
#   2. Create your .env file there with all secrets configured
#
#   3. Copy this hook to ~/.grove/hooks/post-add.d/myapp/

# Path to your pre-built .env file
ENV_SOURCE="$HOME/Code/Worktree/myapp/myapp-env/.env"
ENV_TARGET="${GROVE_PATH}/.env"
ENV_FALLBACK="${GROVE_PATH}/.env.example"

if [[ -f "$ENV_SOURCE" ]]; then
  # ponytail: content equality identifies the generated fallback; add a marker
  # if identical hand-written .env files ever need different treatment.
  if [[ -f "$ENV_TARGET" && ! -L "$ENV_TARGET" && -f "$ENV_FALLBACK" ]] &&
     cmp -s "$ENV_FALLBACK" "$ENV_TARGET"; then
    if ! rm -f "$ENV_TARGET"; then
      echo "  Failed to replace .env.example fallback"
      exit 1
    fi
  fi

  if [[ -e "$ENV_TARGET" || -L "$ENV_TARGET" ]]; then
    echo "  Preserved existing .env"
  elif ln -s "$ENV_SOURCE" "$ENV_TARGET"; then
    echo "  Linked .env → $ENV_SOURCE"
  else
    echo "  Failed to link .env"
    exit 1
  fi
else
  echo "  Pre-built .env not found at $ENV_SOURCE"
  echo "  Keeping .env.example copy as fallback"
fi

exit 0
