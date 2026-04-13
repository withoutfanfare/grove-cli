#!/bin/bash
# Clean up after removing a myapp worktree
#
# Since we use symlinked .env files pointing to a central location,
# the symlink is deleted with the worktree. This hook handles any
# other cleanup specific to myapp.

# Log removal for audit purposes
REMOVAL_LOG="$HOME/Code/Worktree/myapp/removal.log"
if [[ -d "$(dirname "$REMOVAL_LOG")" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') Removed: $GROVE_BRANCH" >> "$REMOVAL_LOG"
  echo "  Logged removal to $REMOVAL_LOG"
fi

# Example: Notify team (Slack webhook, etc.)
# curl -s -X POST -H 'Content-type: application/json' \
#   --data "{\"text\":\"Worktree removed: $GROVE_REPO/$GROVE_BRANCH\"}" \
#   "$SLACK_WEBHOOK_URL"

exit 0
