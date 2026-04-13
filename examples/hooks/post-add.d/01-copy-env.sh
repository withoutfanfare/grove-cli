#!/bin/bash
# Copy .env.example to .env if it doesn't exist
#
# This hook creates a fresh .env file from the template.
# Repo-specific hooks can override this (e.g., to symlink instead).

if [[ -f "${GROVE_PATH}/.env.example" && ! -f "${GROVE_PATH}/.env" ]]; then
  cp "${GROVE_PATH}/.env.example" "${GROVE_PATH}/.env"
  echo "  Created .env from .env.example"
fi

exit 0
