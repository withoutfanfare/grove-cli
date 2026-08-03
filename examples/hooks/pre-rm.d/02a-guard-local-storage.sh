#!/bin/bash
# Refuse removal when a worktree still contains local Laravel storage data.

storage_app="${GROVE_PATH}/storage/app"

if [[ -L "$storage_app" ]]; then
  if ! worktree_root="$(cd "$GROVE_PATH" 2>/dev/null && pwd -P)" ||
     ! storage_target="$(cd "$storage_app" 2>/dev/null && pwd -P)"; then
    echo "Error: Cannot resolve ${storage_app}; refusing removal." >&2
    exit 1
  fi
  case "$storage_target" in
    "$worktree_root"|"$worktree_root"/*)
      echo "Error: ${storage_app} points inside the worktree; refusing removal." >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [[ ! -e "$storage_app" ]]; then
  exit 0
fi

if [[ ! -d "$storage_app" ]]; then
  echo "Error: ${storage_app} is not a directory or shared-storage symlink; refusing removal." >&2
  exit 1
fi

if ! local_data="$(find "$storage_app" -mindepth 1 ! -type d ! \( -type f -name .gitignore \) -print -quit 2>/dev/null)"; then
  echo "Error: Cannot inspect ${storage_app}; refusing removal." >&2
  exit 1
fi

if [[ -n "$local_data" ]]; then
  echo "Error: Refusing removal because ${storage_app} contains local data: ${local_data}" >&2
  echo "Move or back up the data, or link storage/app to shared storage, then retry." >&2
  exit 1
fi

while IFS= read -r -d '' sentinel; do
  relative_path="${sentinel#"$GROVE_PATH"/}"
  if ! git -C "$GROVE_PATH" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
    echo "Error: Refusing removal because ${sentinel} is not tracked by Git." >&2
    exit 1
  fi
  # Compare content hashes directly: `git status` honours the assume-unchanged
  # and skip-worktree bits, which would hide local edits to a sentinel.
  index_hash="$(git -C "$GROVE_PATH" ls-files -s -- "$relative_path" 2>/dev/null)"
  index_hash="${index_hash#* }"
  index_hash="${index_hash%% *}"
  worktree_hash="$(git -C "$GROVE_PATH" hash-object "$sentinel" 2>/dev/null)"
  if [[ -z "$index_hash" || -z "$worktree_hash" || "$worktree_hash" != "$index_hash" ]] ||
     ! git -C "$GROVE_PATH" diff --cached --quiet -- "$relative_path" 2>/dev/null; then
    echo "Error: Refusing removal because ${sentinel} has uncommitted changes." >&2
    exit 1
  fi
done < <(find "$storage_app" -type f -name .gitignore -print0)

exit 0
