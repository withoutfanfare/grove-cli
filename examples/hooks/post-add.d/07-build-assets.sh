#!/bin/bash
# Build frontend assets with npm
#
# Only runs if package.json has a "build" script.
# Skip by setting: GROVE_SKIP_BUILD=true

if [[ "${GROVE_SKIP_BUILD:-}" == "true" ]]; then
  echo "  Skipping asset build (GROVE_SKIP_BUILD=true)"
  exit 0
fi

if [[ ! -f "${GROVE_PATH}/package.json" ]]; then
  exit 0
fi

cd "$GROVE_PATH" || exit 0

# Check if build script exists
if ! grep -q '"build"' package.json 2>/dev/null; then
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "  npm not found - run manually: npm run build"
  exit 0
fi

echo "  Running npm run build..."
if npm run build --silent 2>/dev/null; then
  echo "  Asset build complete"
  exit 0
else
  echo "  Asset build failed - run manually: npm run build"
  exit 1
fi
