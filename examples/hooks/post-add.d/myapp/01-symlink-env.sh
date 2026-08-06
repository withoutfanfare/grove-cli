#!/bin/bash
# Symlink to a pre-built .env file for this specific repo
#
# This runs AFTER the global 04-copy-env.sh hook, replacing the
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

if [[ -f "$ENV_SOURCE" ]]; then
  # Remove the .env created by the global hook
  rm -f "${GROVE_PATH}/.env"

  # Create symlink to pre-built .env
  ln -sf "$ENV_SOURCE" "${GROVE_PATH}/.env"
  echo "  Linked .env → $ENV_SOURCE"
else
  echo "  Pre-built .env not found at $ENV_SOURCE"
  echo "  Keeping .env.example copy as fallback"
fi

exit 0
