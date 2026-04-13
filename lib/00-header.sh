#!/usr/bin/env zsh
set -euo pipefail

readonly VERSION="4.1.0"

# Defaults (can be overridden by config file or env vars)
HERD_ROOT="${HERD_ROOT:-$HOME/Herd}"
HERD_CONFIG="${HERD_CONFIG:-$HOME/Library/Application Support/Herd/config}"
DEFAULT_BASE="${GROVE_BASE_DEFAULT:-origin/staging}"
DEFAULT_EDITOR="${GROVE_EDITOR:-cursor}"

# Cached OS detection (avoids repeated uname/id calls)
readonly GROVE_OS="$(uname -s)"
readonly _GROVE_UID="$(id -u)"

# URL generation defaults
GROVE_URL_SUBDOMAIN="${GROVE_URL_SUBDOMAIN:-}"  # Optional subdomain prefix (e.g., "api" -> api.feature-name.test)

# Database defaults
DB_HOST="${GROVE_DB_HOST:-127.0.0.1}"
DB_USER="${GROVE_DB_USER:-root}"
DB_PASSWORD="${GROVE_DB_PASSWORD:-}"
DB_CREATE="${GROVE_DB_CREATE:-true}"
DB_BACKUP_DIR="${GROVE_DB_BACKUP_DIR:-$HOME/Code/Project Support/Worktree/Database/Backup}"
DB_BACKUP="${GROVE_DB_BACKUP:-true}"

# Hooks directory (for custom post-add scripts, etc.)
GROVE_HOOKS_DIR="${GROVE_HOOKS_DIR:-$HOME/.grove/hooks}"

# Templates directory (for worktree setup templates)
GROVE_TEMPLATES_DIR="${GROVE_TEMPLATES_DIR:-$HOME/.grove/templates}"

# Active template (set via --template flag)
GROVE_TEMPLATE=""

# Global flags
QUIET=false
FORCE=false
JSON_OUTPUT=false
PRETTY_JSON=false
DRY_RUN=false
DELETE_BRANCH=false
DROP_DB=false
NO_BACKUP=false
INTERACTIVE=false

# Parallel operations config
GROVE_MAX_PARALLEL="${GROVE_MAX_PARALLEL:-4}"

# Protected branches (cannot be removed without --force)
PROTECTED_BRANCHES="${GROVE_PROTECTED_BRANCHES:-staging main master}"

# Branch naming patterns (optional validation)
BRANCH_PATTERN="${GROVE_BRANCH_PATTERN:-}"
BRANCH_EXAMPLES="${GROVE_BRANCH_EXAMPLES:-feature/my-feature, bugfix/fix-login}"

# Repository groups for multi-repo operations
REPO_GROUPS="${GROVE_REPO_GROUPS:-}"

# Stale branch threshold (commits behind base before marking stale)
GROVE_STALE_THRESHOLD="${GROVE_STALE_THRESHOLD:-50}"

# Shared dependencies cache directory
GROVE_SHARED_DEPS_DIR="${GROVE_SHARED_DEPS_DIR:-$HOME/.grove/shared-deps}"

# Colour defaults (will be set properly by setup_colors)
C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN=""
