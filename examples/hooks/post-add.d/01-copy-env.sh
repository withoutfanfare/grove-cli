#!/bin/bash
# Copy .env.example to .env if it doesn't exist
#
# This hook creates a fresh .env file from the template.
# Repo-specific hooks can override this (e.g., to symlink instead).

if [[ -f "${GROVE_PATH}/.env.example" && ! -e "${GROVE_PATH}/.env" && ! -L "${GROVE_PATH}/.env" ]]; then
  if install -m 600 "${GROVE_PATH}/.env.example" "${GROVE_PATH}/.env"; then
    echo "  Created .env from .env.example"
  else
    echo "  Failed to create private .env"
    exit 1
  fi
fi

exit 0
