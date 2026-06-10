#!/usr/bin/env zsh
# Restart services after worktree switch
#
# After the -current symlink is updated, this hook restarts the Supervisor
# processes (Horizon, Reverb) so they pick up the new worktree immediately.
#
# Only runs if the repo has a registered service app in grove services.
# If grove services is not configured, this hook exits silently.
#
# Skip by setting: GROVE_SKIP_SERVICES=true

if [[ "${GROVE_SKIP_SERVICES:-}" == "true" ]]; then
  echo "  Skipping service restart (GROVE_SKIP_SERVICES=true)"
  exit 0
fi

# Use grove services restart (idempotent - exits 0 if app not registered)
if command -v grove &> /dev/null; then
  grove services restart "$GROVE_REPO" 2>/dev/null || true
fi

exit 0
