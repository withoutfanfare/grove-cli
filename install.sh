#!/bin/bash
set -e

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

# Check for supported operating system
check_os() {
  local os_name
  os_name="$(uname -s)"

  case "$os_name" in
    Darwin)
      # macOS - supported
      return 0
      ;;
    Linux)
      echo ""
      echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
      echo -e "${RED}║  Linux is not yet supported                               ║${NC}"
      echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "grove is currently macOS-only due to:"
      echo -e "  • Laravel Herd integration (macOS/Windows only)"
      echo -e "  • Homebrew path conventions"
      echo -e "  • macOS-specific path defaults"
      echo ""
      echo -e "${BLUE}Linux support is planned for a future release.${NC}"
      echo -e "See: ${DIM}https://github.com/dannyharding10/grove-cli/blob/main/ROADMAP.md${NC}"
      echo ""
      echo -e "Want to help? Contributions are welcome!"
      echo ""
      exit 1
      ;;
    CYGWIN*|MINGW*|MSYS*|Windows_NT)
      echo ""
      echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
      echo -e "${RED}║  Windows is not yet supported                             ║${NC}"
      echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "grove is currently macOS-only due to:"
      echo -e "  • zsh shell requirement"
      echo -e "  • Unix path conventions"
      echo -e "  • macOS-specific integrations"
      echo ""
      echo -e "${BLUE}Windows support (via WSL) is planned for a future release.${NC}"
      echo -e "See: ${DIM}https://github.com/dannyharding10/grove-cli/blob/main/ROADMAP.md${NC}"
      echo ""
      echo -e "Want to help? Contributions are welcome!"
      echo ""
      exit 1
      ;;
    *)
      echo ""
      echo -e "${RED}Unsupported operating system: $os_name${NC}"
      echo ""
      echo -e "grove currently only supports macOS."
      echo -e "See: ${DIM}https://github.com/dannyharding10/grove-cli/blob/main/ROADMAP.md${NC}"
      echo ""
      exit 1
      ;;
  esac
}

# Run OS check immediately
check_os

# Get the directory where this script lives (the repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults - can be overridden with environment variables
INSTALL_DIR="${GROVE_INSTALL_DIR:-/usr/local/bin}"

# Command-line options
HOOKS_MODE=""  # merge, overwrite, skip, or empty for interactive
QUIET=false

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --merge       Install new example hooks, keep existing (default when interactive)"
  echo "  --overwrite   Replace all hooks with examples"
  echo "  --skip-hooks  Don't install or modify hooks"
  echo "  --quiet       Minimal output"
  echo "  -h, --help    Show this help"
  echo ""
  echo "Environment variables:"
  echo "  GROVE_INSTALL_DIR      Installation directory (default: /usr/local/bin)"
  echo "  GROVE_COMPLETIONS_DIR  Completions directory (auto-detected)"
  exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --merge)
      HOOKS_MODE="merge"
      shift
      ;;
    --overwrite)
      HOOKS_MODE="overwrite"
      shift
      ;;
    --skip-hooks)
      HOOKS_MODE="skip"
      shift
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      usage
      ;;
  esac
done

# Auto-detect best completions directory
detect_completions_dir() {
  # Prefer Homebrew's site-functions (most Mac devs have this)
  if [[ -d "/opt/homebrew/share/zsh/site-functions" ]]; then
    echo "/opt/homebrew/share/zsh/site-functions"  # Apple Silicon
  elif [[ -d "/usr/local/share/zsh/site-functions" ]]; then
    echo "/usr/local/share/zsh/site-functions"  # Intel Mac
  else
    echo "$HOME/.zsh/completions"  # Fallback
  fi
}

COMPLETIONS_DIR="${GROVE_COMPLETIONS_DIR:-$(detect_completions_dir)}"

print_header() {
  echo ""
  echo -e "${BLUE}=======================================${NC}"
  echo -e "${BLUE}  ${GREEN}grove${NC} - Git Worktree Manager"
  echo -e "${BLUE}  for Laravel Herd${NC}"
  echo -e "${BLUE}=======================================${NC}"
  echo ""
}

check_requirements() {
  local missing=()
  local optional_missing=()

  echo -e "${BLUE}Checking dependencies...${NC}"
  echo ""
  echo -e "  ${DIM}Required:${NC}"

  # Check for zsh (required)
  if ! command -v zsh &> /dev/null; then
    missing+=("zsh")
    echo -e "  ${RED}✗${NC} zsh"
  else
    echo -e "  ${GREEN}✓${NC} zsh"
  fi

  # Check for git (required)
  if ! command -v git &> /dev/null; then
    missing+=("git")
    echo -e "  ${RED}✗${NC} git"
  else
    echo -e "  ${GREEN}✓${NC} git"
  fi

  echo ""
  echo -e "  ${DIM}Optional (for full functionality):${NC}"

  # Check for fzf (optional - interactive mode)
  if ! command -v fzf &> /dev/null; then
    optional_missing+=("fzf")
    echo -e "  ${YELLOW}○${NC} fzf ${DIM}- interactive selection (grove add -i)${NC}"
  else
    echo -e "  ${GREEN}✓${NC} fzf"
  fi

  # Check for jq (optional - JSON formatting)
  if ! command -v jq &> /dev/null; then
    optional_missing+=("jq")
    echo -e "  ${YELLOW}○${NC} jq ${DIM}- pretty JSON output (--pretty flag)${NC}"
  else
    echo -e "  ${GREEN}✓${NC} jq"
  fi

  # Check for mysql (optional - database management)
  if ! command -v mysql &> /dev/null; then
    optional_missing+=("mysql")
    echo -e "  ${YELLOW}○${NC} mysql ${DIM}- database creation/backup${NC}"
  else
    echo -e "  ${GREEN}✓${NC} mysql"
  fi

  echo ""
  echo -e "  ${DIM}Framework-specific (for hooks):${NC}"

  # Check for Laravel Herd
  if ! command -v herd &> /dev/null; then
    echo -e "  ${YELLOW}○${NC} herd ${DIM}- Laravel Herd HTTPS sites${NC}"
  else
    echo -e "  ${GREEN}✓${NC} herd"
  fi

  # Check for composer
  if ! command -v composer &> /dev/null; then
    echo -e "  ${YELLOW}○${NC} composer ${DIM}- PHP dependency management${NC}"
  else
    echo -e "  ${GREEN}✓${NC} composer"
  fi

  # Check for npm/node
  if ! command -v npm &> /dev/null; then
    echo -e "  ${YELLOW}○${NC} npm ${DIM}- Node.js package management${NC}"
  else
    echo -e "  ${GREEN}✓${NC} npm"
  fi

  echo ""

  # Show installation instructions for missing required dependencies
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Missing required dependencies: ${missing[*]}${NC}"
    echo ""
    echo -e "${BLUE}Installation instructions:${NC}"
    echo ""
    for dep in "${missing[@]}"; do
      case "$dep" in
        zsh)
          echo -e "  ${YELLOW}zsh:${NC}"
          echo -e "    macOS: ${DIM}(pre-installed, check /bin/zsh)${NC}"
          echo -e "    Linux: ${DIM}sudo apt install zsh${NC}"
          echo ""
          ;;
        git)
          echo -e "  ${YELLOW}git:${NC}"
          echo -e "    macOS: ${DIM}xcode-select --install${NC}"
          echo -e "    Linux: ${DIM}sudo apt install git${NC}"
          echo ""
          ;;
      esac
    done
    exit 1
  fi

  # Show installation instructions for missing optional dependencies
  if [[ ${#optional_missing[@]} -gt 0 ]]; then
    echo -e "${YELLOW}To enable all features, install optional dependencies:${NC}"
    echo ""

    # Check if Homebrew is available
    if command -v brew &> /dev/null; then
      local brew_deps=()
      for dep in "${optional_missing[@]}"; do
        brew_deps+=("$dep")
      done
      echo -e "  ${DIM}brew install ${brew_deps[*]}${NC}"
    else
      for dep in "${optional_missing[@]}"; do
        case "$dep" in
          fzf)
            echo -e "  ${YELLOW}fzf:${NC} ${DIM}https://github.com/junegunn/fzf#installation${NC}"
            ;;
          jq)
            echo -e "  ${YELLOW}jq:${NC} ${DIM}https://jqlang.github.io/jq/download/${NC}"
            ;;
          mysql)
            echo -e "  ${YELLOW}mysql:${NC} ${DIM}https://dev.mysql.com/downloads/mysql/${NC}"
            ;;
        esac
      done
    fi
    echo ""
  fi
}

install_script() {
  echo -e "${BLUE}Installing grove...${NC}"

  # Create install directory if needed
  if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "  Creating $INSTALL_DIR..."
    sudo mkdir -p "$INSTALL_DIR"
  fi

  # Remove existing file/symlink
  if [[ -e "$INSTALL_DIR/grove" || -L "$INSTALL_DIR/grove" ]]; then
    if [[ -w "$INSTALL_DIR" ]]; then
      rm -f "$INSTALL_DIR/grove"
    else
      sudo rm -f "$INSTALL_DIR/grove"
    fi
  fi

  # Create symlink to the repository version
  if [[ -w "$INSTALL_DIR" ]]; then
    ln -sf "$SCRIPT_DIR/grove" "$INSTALL_DIR/grove"
  else
    sudo ln -sf "$SCRIPT_DIR/grove" "$INSTALL_DIR/grove"
  fi
  echo -e "  ${GREEN}✓${NC} Linked grove to $INSTALL_DIR/grove"
  echo -e "    ${DIM}→ $SCRIPT_DIR/grove${NC}"
}

install_completions() {
  echo -e "${BLUE}Installing zsh completions...${NC}"

  # Create completions directory if needed
  if [[ ! -d "$COMPLETIONS_DIR" ]]; then
    if [[ -w "$(dirname "$COMPLETIONS_DIR")" ]]; then
      mkdir -p "$COMPLETIONS_DIR"
    else
      sudo mkdir -p "$COMPLETIONS_DIR"
    fi
  fi

  # Remove existing file/symlink
  if [[ -e "$COMPLETIONS_DIR/_grove" || -L "$COMPLETIONS_DIR/_grove" ]]; then
    if [[ -w "$COMPLETIONS_DIR" ]]; then
      rm -f "$COMPLETIONS_DIR/_grove"
    else
      sudo rm -f "$COMPLETIONS_DIR/_grove"
    fi
  fi

  # Create symlink
  if [[ -w "$COMPLETIONS_DIR" ]]; then
    ln -sf "$SCRIPT_DIR/_grove" "$COMPLETIONS_DIR/_grove"
  else
    sudo ln -sf "$SCRIPT_DIR/_grove" "$COMPLETIONS_DIR/_grove"
  fi
  echo -e "  ${GREEN}✓${NC} Linked completions to $COMPLETIONS_DIR/_grove"
  echo -e "    ${DIM}→ $SCRIPT_DIR/_grove${NC}"
}

create_config() {
  local config_file="$HOME/.groverc"

  if [[ -f "$config_file" ]]; then
    echo -e "${BLUE}Config file...${NC}"
    echo -e "  ${GREEN}✓${NC} Already exists at $config_file"
    return
  fi

  echo -e "${BLUE}Creating config file...${NC}"

  # Detect Herd root
  local herd_root="$HOME/Herd"
  if [[ -d "$HOME/Herd" ]]; then
    herd_root="$HOME/Herd"
  elif [[ -d "$HOME/Sites" ]]; then
    herd_root="$HOME/Sites"
  fi

  cat > "$config_file" << EOF
# grove configuration file
# See: https://github.com/dannyharding10/grove-cli

# Where your Herd/Valet sites live
HERD_ROOT=$herd_root

# Default base branch for new worktrees
DEFAULT_BASE=origin/staging

# Editor to open with 'grove code' (cursor, code, zed, etc.)
DEFAULT_EDITOR=cursor

# Database connection
DB_HOST=127.0.0.1
DB_USER=root
DB_PASSWORD=
DB_CREATE=true

# Database backup on removal
DB_BACKUP=true
DB_BACKUP_DIR="\$HOME/Code/Project Support/Worktree/Database/Backup"

# Protected branches (require -f to remove)
PROTECTED_BRANCHES="staging main master"
EOF

  echo -e "  ${GREEN}✓${NC} Created config at $config_file"
}

create_hooks_dir() {
  local hooks_dir="$HOME/.grove/hooks"
  local hook_dirs=("pre-add.d" "post-add.d" "pre-rm.d" "post-rm.d" "post-pull.d" "post-sync.d")

  echo -e "${BLUE}Setting up hooks directory...${NC}"

  # Create main hooks directory
  if [[ ! -d "$hooks_dir" ]]; then
    mkdir -p "$hooks_dir"
    echo -e "  ${GREEN}✓${NC} Created $hooks_dir"
  else
    echo -e "  ${GREEN}✓${NC} Already exists at $hooks_dir"
  fi

  # Create all hook subdirectories
  for hook_subdir in "${hook_dirs[@]}"; do
    if [[ ! -d "$hooks_dir/$hook_subdir" ]]; then
      mkdir -p "$hooks_dir/$hook_subdir"
      echo -e "  ${GREEN}✓${NC} Created $hooks_dir/$hook_subdir"
    fi
  done
}

install_example_hooks() {
  local hooks_dir="$HOME/.grove/hooks"
  local examples_dir="$SCRIPT_DIR/examples/hooks"

  # Skip if no examples directory
  if [[ ! -d "$examples_dir" ]]; then
    return
  fi

  echo -e "${BLUE}Example hooks...${NC}"

  # Count existing hook files (excluding directories and README)
  local existing_count
  existing_count=$(find "$hooks_dir" -type f ! -name "README*" 2>/dev/null | wc -l | tr -d ' ')

  # If HOOKS_MODE not set, determine interactively or use defaults
  if [[ -z "$HOOKS_MODE" ]]; then
    if [[ "$existing_count" -eq 0 ]]; then
      # Fresh install - default to merge (install all examples)
      HOOKS_MODE="merge"
      echo -e "  ${DIM}Installing example hooks...${NC}"
    else
      # Existing hooks - ask user
      echo ""
      echo -e "  Found ${YELLOW}$existing_count${NC} existing hook file(s)."
      echo ""
      echo -e "  How would you like to handle example hooks?"
      echo -e "    ${GREEN}[M]${NC}erge  - Add new examples, keep your existing hooks (default)"
      echo -e "    ${YELLOW}[O]${NC}verwrite - Replace all with examples (backs up existing)"
      echo -e "    ${DIM}[S]${NC}kip  - Don't modify hooks"
      echo ""
      read -r -p "  Choice [M/o/s]: " choice
      case "${choice:-m}" in
        [Oo]*)
          HOOKS_MODE="overwrite"
          ;;
        [Ss]*)
          HOOKS_MODE="skip"
          ;;
        *)
          HOOKS_MODE="merge"
          ;;
      esac
    fi
  fi

  case "$HOOKS_MODE" in
    skip)
      echo -e "  ${DIM}Skipped (use --merge or --overwrite to install examples)${NC}"
      return
      ;;
    overwrite)
      install_hooks_overwrite "$hooks_dir" "$examples_dir"
      ;;
    merge|*)
      install_hooks_merge "$hooks_dir" "$examples_dir"
      ;;
  esac
}

install_hooks_merge() {
  local hooks_dir="$1"
  local examples_dir="$2"
  local installed=0
  local skipped=0

  # Find all example files (excluding README and directories)
  while IFS= read -r -d '' src_file; do
    # Get relative path from examples_dir
    local rel_path="${src_file#$examples_dir/}"
    local dest_file="$hooks_dir/$rel_path"
    local dest_dir="$(dirname "$dest_file")"

    # Create destination directory if needed
    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"

    # Only copy if destination doesn't exist
    if [[ ! -e "$dest_file" ]]; then
      cp "$src_file" "$dest_file"
      chmod +x "$dest_file"
      ((installed++))
      if [[ "$QUIET" != true ]]; then
        echo -e "  ${GREEN}+${NC} $rel_path"
      fi
    else
      ((skipped++))
    fi
  done < <(find "$examples_dir" -type f ! -name "README*" -print0 2>/dev/null)

  if [[ "$installed" -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Installed $installed new hook(s)"
  fi
  if [[ "$skipped" -gt 0 ]]; then
    echo -e "  ${DIM}Skipped $skipped existing hook(s)${NC}"
  fi
  if [[ "$installed" -eq 0 && "$skipped" -eq 0 ]]; then
    echo -e "  ${DIM}No example hooks to install${NC}"
  fi
}

install_hooks_overwrite() {
  local hooks_dir="$1"
  local examples_dir="$2"
  local installed=0

  # Backup existing hooks
  local backup_dir="$HOME/.grove/hooks.backup.$(date +%Y%m%d_%H%M%S)"
  local has_existing=false

  # Check if there are files to backup
  if [[ -n "$(find "$hooks_dir" -type f ! -name "README*" 2>/dev/null)" ]]; then
    has_existing=true
    mkdir -p "$backup_dir"

    # Copy existing structure to backup
    find "$hooks_dir" -type f ! -name "README*" -print0 2>/dev/null | while IFS= read -r -d '' file; do
      local rel_path="${file#$hooks_dir/}"
      local backup_file="$backup_dir/$rel_path"
      mkdir -p "$(dirname "$backup_file")"
      cp "$file" "$backup_file"
    done

    echo -e "  ${YELLOW}!${NC} Backed up existing hooks to:"
    echo -e "    ${DIM}$backup_dir${NC}"

    # Remove existing hooks (but keep directories)
    find "$hooks_dir" -type f ! -name "README*" -delete 2>/dev/null
  fi

  # Install all examples
  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#$examples_dir/}"
    local dest_file="$hooks_dir/$rel_path"
    local dest_dir="$(dirname "$dest_file")"

    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
    cp "$src_file" "$dest_file"
    chmod +x "$dest_file"
    ((installed++))
    if [[ "$QUIET" != true ]]; then
      echo -e "  ${GREEN}+${NC} $rel_path"
    fi
  done < <(find "$examples_dir" -type f ! -name "README*" -print0 2>/dev/null)

  if [[ "$installed" -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Installed $installed hook(s)"
  fi
}

check_path() {
  # Check if INSTALL_DIR is in PATH
  if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}Note:${NC} $INSTALL_DIR is not in your PATH."
    echo ""
    echo "Add this to your ~/.zshrc:"
    echo ""
    echo -e "  ${YELLOW}export PATH=\"$INSTALL_DIR:\$PATH\"${NC}"
    echo ""
  fi
}

check_completions_fpath() {
  # Only needed for custom completions directory
  if [[ "$COMPLETIONS_DIR" == "$HOME/.zsh/completions" ]]; then
    echo ""
    echo -e "${YELLOW}Note:${NC} Add completions to your ~/.zshrc:"
    echo ""
    echo -e "  ${YELLOW}fpath=(~/.zsh/completions \$fpath)${NC}"
    echo -e "  ${YELLOW}autoload -Uz compinit && compinit${NC}"
    echo ""
  fi
}

print_success() {
  echo ""
  echo -e "${GREEN}Installation complete!${NC}"
  echo ""
  echo -e "${BLUE}Verify installation:${NC}"
  echo ""
  echo -e "  ${YELLOW}grove --version${NC}"
  echo -e "  ${YELLOW}grove doctor${NC}"
  echo ""
  echo -e "${BLUE}Quick start:${NC}"
  echo ""
  echo -e "  ${YELLOW}grove clone git@github.com:your-org/your-app.git${NC}"
  echo -e "  ${YELLOW}grove add your-app feature/my-feature${NC}"
  echo -e "  ${YELLOW}cd \"\$(grove switch your-app)\"${NC}"
  echo ""
  echo -e "${DIM}Updates: Pull this repo and changes are immediately available.${NC}"
  echo ""
}

# Main
print_header
check_requirements
install_script
install_completions
create_config
create_hooks_dir
install_example_hooks
check_path
check_completions_fpath
print_success
