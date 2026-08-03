#!/bin/bash
# Run npm install for Node.js projects
#
# Only runs if package.json exists.
# Skip by setting: GROVE_SKIP_NPM=true

if [[ "${GROVE_SKIP_NPM:-}" == "true" ]]; then
  echo "  Skipping npm install (GROVE_SKIP_NPM=true)"
  exit 0
fi

if [[ ! -f "${GROVE_PATH}/package.json" ]]; then
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  # Fail loudly: a worktree with no node_modules looks fine until every page
  # 500s on a missing asset manifest.
  echo "  npm not found - dependencies NOT installed. Run manually: npm install"
  exit 1
fi

cd "$GROVE_PATH" || exit 0

echo "  Running npm install..."
if npm install --silent 2>&1; then
  echo "  npm install complete"
  exit 0
else
  echo "  npm install failed - run manually: npm install"
  exit 1
fi
