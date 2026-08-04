#!/bin/bash
# Restart devctl services after worktree switch
#
# After the -current symlink is updated, this hook restarts the Horizon
# and scheduler services so they pick up the new worktree immediately.
#
# Only runs for apps managed by devctl: knotbook, scooda, modernprintworks, enneagram
#
# Skip by setting: GROVE_SKIP_DEVCTL=true

if [[ "${GROVE_SKIP_DEVCTL:-}" == "true" ]]; then
  echo "  Skipping devctl restart (GROVE_SKIP_DEVCTL=true)"
  exit 0
fi

# Check if devctl is available
if ! command -v devctl &> /dev/null; then
  echo "  Skipping devctl restart (devctl not found)"
  exit 0
fi

# Validate required environment variable
if [[ -z "$GROVE_REPO" ]]; then
  echo "  Skipping devctl restart - missing GROVE_REPO"
  exit 0
fi

# Map repo names to devctl app names
case "$GROVE_REPO" in
  knotbook|scooda|modernprintworks)
    app="$GROVE_REPO"
    ;;
  enneagram|enneagram-assessment)
    app="enneagram"
    ;;
  *)
    echo "  Skipping devctl restart - $GROVE_REPO not managed by devctl"
    exit 0
    ;;
esac

echo "  Restarting $app services..."

# Restart supervisor processes (Horizon + Reverb if applicable)
if devctl restart "$app" > /dev/null 2>&1; then
  echo "  Restarted $app Horizon"
else
  echo "  Failed to restart $app services (may not be running)"
fi

exit 0
