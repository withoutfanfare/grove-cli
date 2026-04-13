#!/usr/bin/env zsh
# 99-main.sh - Main entry point, usage, and flag parsing

usage() {
  print -r -- ""
  print -r -- "${C_BOLD}grove${C_RESET} v$VERSION - Git worktree manager"
  print -r -- ""
  print -r -- "${C_BOLD}USAGE${C_RESET}"
  print -r -- "  grove [flags] <command> [args]"
  print -r -- ""
  print -r -- "${C_BOLD}CORE COMMANDS${C_RESET}"
  print -r -- "  ${C_GREEN}add${C_RESET}      ${C_DIM}<repo> <branch> [base]${C_RESET}     Create worktree"
  print -r -- "           ${C_DIM}--template=<name>, -t <name>${C_RESET}  Use template"
  print -r -- "           ${C_DIM}--dry-run${C_RESET}                     Preview without creating"
  print -r -- "           ${C_DIM}--interactive, -i${C_RESET}             Guided creation wizard"
  print -r -- "  ${C_GREEN}rm${C_RESET}       ${C_DIM}<repo> [branch]${C_RESET}            Remove worktree"
  print -r -- "  ${C_GREEN}move${C_RESET}     ${C_DIM}<repo> <branch> <new-name>${C_RESET}  Rename/move worktree"
  print -r -- "  ${C_GREEN}ls${C_RESET}       ${C_DIM}<repo>${C_RESET}                     List worktrees"
  print -r -- "  ${C_GREEN}repos${C_RESET}                               List all repositories"
  print -r -- "  ${C_GREEN}clone${C_RESET}    ${C_DIM}<url> [name] [branch]${C_RESET}      Clone as bare repo"
  print -r -- ""
  print -r -- "${C_BOLD}GIT COMMANDS${C_RESET} ${C_DIM}(auto-detect repo/branch when run from worktree)${C_RESET}"
  print -r -- "  ${C_GREEN}status${C_RESET}   ${C_DIM}<repo>${C_RESET}                     Dashboard view of all worktrees"
  print -r -- "  ${C_GREEN}pull${C_RESET}     ${C_DIM}[repo] [branch]${C_RESET}            Pull latest changes"
  print -r -- "  ${C_GREEN}pull-all${C_RESET} ${C_DIM}<repo>${C_RESET}                     Pull all worktrees (parallel)"
  print -r -- "  ${C_GREEN}sync${C_RESET}     ${C_DIM}[repo] [branch] [base]${C_RESET}     Rebase onto base branch"
  print -r -- "  ${C_GREEN}diff${C_RESET}     ${C_DIM}[repo] [branch] [base]${C_RESET}     Show diff against base branch"
  print -r -- "  ${C_GREEN}summary${C_RESET}  ${C_DIM}[repo] [branch] [base]${C_RESET}     Summarise changes vs base branch"
  print -r -- "  ${C_GREEN}log${C_RESET}      ${C_DIM}[repo] [branch] [-n N]${C_RESET}     Show recent commits (default: 5)"
  print -r -- "  ${C_GREEN}changes${C_RESET}  ${C_DIM}[repo] [branch]${C_RESET}            List uncommitted file changes"
  print -r -- "  ${C_GREEN}prune${C_RESET}    ${C_DIM}<repo>${C_RESET}                     Clean up stale worktrees"
  print -r -- "           ${C_DIM}--all-repos${C_RESET}                  Prune across all repositories"
  print -r -- ""
  print -r -- "${C_BOLD}PARALLEL COMMANDS${C_RESET}"
  print -r -- "  ${C_GREEN}build-all${C_RESET} ${C_DIM}<repo>${C_RESET}                    npm run build on all"
  print -r -- "  ${C_GREEN}exec-all${C_RESET}  ${C_DIM}<repo> <cmd>${C_RESET}              Run command on all"
  print -r -- ""
  print -r -- "${C_BOLD}LARAVEL COMMANDS${C_RESET} ${C_DIM}(auto-detect when run from worktree)${C_RESET}"
  print -r -- "  ${C_GREEN}fresh${C_RESET}    ${C_DIM}[repo] [branch]${C_RESET}            migrate:fresh + npm ci + build"
  print -r -- "  ${C_GREEN}migrate${C_RESET}  ${C_DIM}[repo] [branch]${C_RESET}            Run artisan migrate"
  print -r -- "  ${C_GREEN}tinker${C_RESET}   ${C_DIM}[repo] [branch]${C_RESET}            Run artisan tinker"
  print -r -- ""
  print -r -- "${C_BOLD}NAVIGATION${C_RESET} ${C_DIM}(auto-detect when run from worktree)${C_RESET}"
  print -r -- "  ${C_GREEN}code${C_RESET}     ${C_DIM}[repo] [branch]${C_RESET}            Open in editor"
  print -r -- "  ${C_GREEN}open${C_RESET}     ${C_DIM}[repo] [branch]${C_RESET}            Open URL in browser"
  print -r -- "  ${C_GREEN}cd${C_RESET}       ${C_DIM}[repo] [branch]${C_RESET}            Print worktree path"
  print -r -- "  ${C_GREEN}switch${C_RESET}   ${C_DIM}<repo> [branch]${C_RESET}            cd + code + open in one"
  print -r -- "  ${C_GREEN}exec${C_RESET}     ${C_DIM}<repo> <branch> <cmd>${C_RESET}      Run command in worktree"
  print -r -- ""
  print -r -- "${C_BOLD}BRANCH SHORTCUTS${C_RESET}"
  print -r -- "  ${C_YELLOW}@1, @2, @3${C_RESET}                          Recent worktrees (@1 = most recent)"
  print -r -- "  ${C_YELLOW}feat-auth${C_RESET}                           Fuzzy match: feature/auth-improvements"
  print -r -- ""
  print -r -- "${C_BOLD}UTILITIES${C_RESET}"
  print -r -- "  ${C_GREEN}config${C_RESET}                              Show current configuration"
  print -r -- "  ${C_GREEN}setup${C_RESET}                               First-time configuration wizard"
  print -r -- "  ${C_GREEN}doctor${C_RESET}                              Check system requirements"
  print -r -- "  ${C_GREEN}health${C_RESET}   ${C_DIM}<repo>${C_RESET}                     Check repository health"
  print -r -- "  ${C_GREEN}branches${C_RESET} ${C_DIM}<repo>${C_RESET}                     List available branches"
  print -r -- "  ${C_GREEN}info${C_RESET}     ${C_DIM}[repo] [branch]${C_RESET}            Detailed worktree information"
  print -r -- "  ${C_GREEN}recent${C_RESET}   ${C_DIM}[count]${C_RESET}                    List recently accessed worktrees"
  print -r -- "  ${C_GREEN}clean${C_RESET}    ${C_DIM}[repo]${C_RESET}                     Remove deps from inactive worktrees"
  print -r -- "  ${C_GREEN}alias${C_RESET}    ${C_DIM}[add|rm] <name> [target]${C_RESET}   Manage branch aliases"
  print -r -- "  ${C_GREEN}group${C_RESET}    ${C_DIM}[add|rm|show] <name> ...${C_RESET}   Manage repository groups"
  print -r -- "  ${C_GREEN}repair${C_RESET}   ${C_DIM}[repo]${C_RESET}                     Fix common issues"
  print -r -- "           ${C_DIM}--recovery${C_RESET}                   Attempt aggressive recovery"
  print -r -- "  ${C_GREEN}upgrade${C_RESET}                             Self-update grove to latest version"
  print -r -- "  ${C_GREEN}report${C_RESET}   ${C_DIM}<repo> [--output <file>]${C_RESET}  Generate markdown status report"
  print -r -- "  ${C_GREEN}cleanup-herd${C_RESET}                        Remove orphaned Herd nginx configs"
  print -r -- "  ${C_GREEN}unlock${C_RESET}   ${C_DIM}[repo]${C_RESET}                    Remove stale git lock files"
  print -r -- "  ${C_GREEN}share-deps${C_RESET} ${C_DIM}[enable|disable|status]${C_RESET} Share vendor/node_modules"
  print -r -- ""
  print -r -- "${C_BOLD}FLAGS${C_RESET}"
  print -r -- "  ${C_YELLOW}-q, --quiet${C_RESET}          Suppress informational output"
  print -r -- "  ${C_YELLOW}-f, --force${C_RESET}          Skip confirmations / force protected branch removal"
  print -r -- "  ${C_YELLOW}-i, --interactive${C_RESET}    Launch interactive worktree creation wizard"
  print -r -- "  ${C_YELLOW}--json${C_RESET}               Output in JSON format"
  print -r -- "  ${C_YELLOW}--pretty${C_RESET}             Pretty-print JSON output with colours"
  print -r -- "  ${C_YELLOW}--dry-run${C_RESET}            Preview actions without executing (grove add)"
  print -r -- "  ${C_YELLOW}-t, --template${C_RESET}       Apply template when creating worktree"
  print -r -- "  ${C_YELLOW}--delete-branch${C_RESET}      Delete branch when removing worktree"
  print -r -- "  ${C_YELLOW}--drop-db${C_RESET}            Drop database when removing worktree"
  print -r -- "  ${C_YELLOW}--no-backup${C_RESET}          Skip database backup when removing worktree"
  print -r -- "  ${C_YELLOW}--no-cache${C_RESET}           Bypass fetch cache (always fetch fresh)"
  print -r -- "  ${C_YELLOW}--refresh${C_RESET}            Clear fetch cache before running command"
  print -r -- "  ${C_YELLOW}-v, --version${C_RESET}        Show version (add --check to check for updates)"
  print -r -- ""
  print -r -- "${C_BOLD}EXAMPLES${C_RESET}"
  print -r -- "  ${C_DIM}# Set up a new project${C_RESET}"
  print -r -- "  grove clone git@github.com:org/myapp.git"
  print -r -- "  grove add myapp feature/login"
  print -r -- ""
  print -r -- "  ${C_DIM}# Interactive worktree creation${C_RESET}"
  print -r -- "  grove add --interactive"
  print -r -- ""
  print -r -- "  ${C_DIM}# Navigate to worktree${C_RESET}"
  print -r -- "  cd \"\$(grove cd myapp feature/login)\""
  print -r -- ""
  print -r -- "  ${C_DIM}# Interactive selection (requires fzf)${C_RESET}"
  print -r -- "  grove code myapp              ${C_DIM}# opens fzf picker${C_RESET}"
  print -r -- ""
  print -r -- "  ${C_DIM}# Run command in worktree${C_RESET}"
  print -r -- "  grove exec myapp feature/login php artisan migrate"
  print -r -- ""
  print -r -- "  ${C_DIM}# Parallel operations${C_RESET}"
  print -r -- "  grove pull-all myapp          ${C_DIM}# pull all worktrees${C_RESET}"
  print -r -- "  grove build-all myapp         ${C_DIM}# build all worktrees${C_RESET}"
  print -r -- ""
  print -r -- "  ${C_DIM}# Use template with dry-run preview${C_RESET}"
  print -r -- "  grove add myapp feature/api --template=backend --dry-run"
  print -r -- ""
  print -r -- "${C_BOLD}AVAILABLE TEMPLATES${C_RESET}"
  list_templates
  print -r -- ""
  print -r -- "  ${C_DIM}Run 'grove templates' for details or 'grove templates <name>' to view a template${C_RESET}"
  print -r -- ""
  print -r -- "${C_BOLD}ENVIRONMENT${C_RESET}"
  print -r -- "  ${C_YELLOW}HERD_ROOT${C_RESET}              Herd directory ${C_DIM}(default: \$HOME/Herd)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_BASE_DEFAULT${C_RESET}   Default base branch ${C_DIM}(default: origin/staging)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_EDITOR${C_RESET}         Editor command ${C_DIM}(default: cursor)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_CONFIG${C_RESET}         Config file path ${C_DIM}(default: ~/.groverc)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_URL_SUBDOMAIN${C_RESET}  Optional URL subdomain ${C_DIM}(e.g., api -> api.feature.test)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_HOOKS_DIR${C_RESET}      Hooks directory ${C_DIM}(default: ~/.grove/hooks)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_MAX_PARALLEL${C_RESET}   Max parallel operations ${C_DIM}(default: 4)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_FETCH_CACHE_TTL${C_RESET} Fetch cache TTL in seconds ${C_DIM}(default: 30, 0 to disable)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_DB_HOST${C_RESET}        MySQL host ${C_DIM}(default: 127.0.0.1)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_DB_USER${C_RESET}        MySQL user ${C_DIM}(default: root)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_DB_PASSWORD${C_RESET}    MySQL password ${C_DIM}(default: empty)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_DB_CREATE${C_RESET}      Auto-create database ${C_DIM}(default: true)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_DB_BACKUP${C_RESET}      Backup database on remove ${C_DIM}(default: true)${C_RESET}"
  print -r -- "  ${C_YELLOW}GROVE_DB_BACKUP_DIR${C_RESET}  Backup directory ${C_DIM}(default: ~/Code/Project Support/...)${C_RESET}"
  print -r -- ""
  print -r -- "${C_BOLD}CONFIG FILE${C_RESET}"
  print -r -- "  Create ${C_CYAN}~/.groverc${C_RESET} or ${C_CYAN}\$HERD_ROOT/.groveconfig${C_RESET} with:"
  print -r -- "    HERD_ROOT=/path/to/herd"
  print -r -- "    DEFAULT_BASE=origin/main"
  print -r -- "    DEFAULT_EDITOR=code"
  print -r -- "    GROVE_URL_SUBDOMAIN=api       ${C_DIM}# optional: api.feature.test${C_RESET}"
  print -r -- "    DB_USER=root"
  print -r -- "    DB_PASSWORD=secret"
  print -r -- "    DB_BACKUP_DIR=/path/to/backups"
  print -r -- ""
  print -r -- "${C_BOLD}HOOKS${C_RESET}"
  print -r -- "  Create executable scripts in ${C_CYAN}~/.grove/hooks/${C_RESET} to run custom commands:"
  print -r -- ""
  print -r -- "  ${C_GREEN}pre-add${C_RESET}      Run before worktree creation (can abort)"
  print -r -- "  ${C_GREEN}post-add${C_RESET}     Run after worktree creation"
  print -r -- "  ${C_GREEN}pre-rm${C_RESET}       Run before worktree removal (can abort)"
  print -r -- "  ${C_GREEN}post-rm${C_RESET}      Run after worktree removal"
  print -r -- "  ${C_GREEN}post-pull${C_RESET}    Run after grove pull succeeds"
  print -r -- "  ${C_GREEN}post-sync${C_RESET}    Run after grove sync succeeds"
  print -r -- "  ${C_GREEN}post-switch${C_RESET}  Run after grove switch succeeds"
  print -r -- ""
  print -r -- "  ${C_DIM}Available environment variables in hooks:${C_RESET}"
  print -r -- "    GROVE_REPO       Repository name"
  print -r -- "    GROVE_BRANCH     Branch name"
  print -r -- "    GROVE_PATH       Worktree path"
  print -r -- "    GROVE_URL        Application URL"
  print -r -- "    GROVE_DB_NAME    Database name"
  print -r -- ""
  print -r -- "  ${C_DIM}Example ~/.grove/hooks/post-add:${C_RESET}"
  print -r -- "    #!/bin/bash"
  print -r -- "    npm ci && npm run build"
  print -r -- "    php artisan migrate"
  print -r -- ""
  print -r -- "  ${C_DIM}Multiple hooks: Create ~/.grove/hooks/post-add.d/ with numbered scripts${C_RESET}"
  print -r -- "  ${C_DIM}Repo-specific: Create ~/.grove/hooks/post-add.d/<repo>/ for repo-only hooks${C_RESET}"
  print -r -- ""
}

# Parse global flags (can appear anywhere in command line)
parse_flags() {
  REMAINING_ARGS=()
  local show_version=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -q|--quiet) QUIET=true ;;
      -f|--force) FORCE=true ;;
      -i|--interactive) INTERACTIVE=true ;;
      --json) JSON_OUTPUT=true ;;
      --delete-branch) DELETE_BRANCH=true ;;
      --drop-db) DROP_DB=true ;;
      --no-backup) NO_BACKUP=true ;;
      --dry-run) DRY_RUN=true ;;
      --pretty) PRETTY_JSON=true ;;
      --check) VERSION_CHECK=true ;;
      --all-repos) ALL_REPOS=true ;;
      --recovery) RECOVERY_MODE=true ;;
      --no-cache) GROVE_FETCH_CACHE_TTL=0 ;;
      --refresh) clear_fetch_cache ;;
      --template=*)
        GROVE_TEMPLATE="${1#--template=}"
        if [[ -z "$GROVE_TEMPLATE" ]]; then
          setup_colors
          die "Template name cannot be empty"
        fi
        ;;
      -t)
        shift
        if [[ -z "${1:-}" || "$1" == -* ]]; then
          setup_colors
          die "Template name required after -t flag"
        fi
        GROVE_TEMPLATE="$1"
        ;;
      -v|--version) show_version=true ;;
      -h|--help|help) setup_colors; usage; exit 0 ;;
      -n)
        # -n is used by grove log for limiting commit count - pass through to command
        REMAINING_ARGS+=("$1")
        if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
          shift
          REMAINING_ARGS+=("$1")
        fi
        ;;
      -n*)
        # Handle -n5 format (no space) - pass through to command
        REMAINING_ARGS+=("$1")
        ;;
      -*) setup_colors; die "Unknown flag: $1" ;;
      *) REMAINING_ARGS+=("$1") ;;
    esac
    shift
  done

  # Handle --version after all flags parsed (so --check works regardless of order)
  if [[ "$show_version" == true ]]; then
    if [[ "${VERSION_CHECK:-false}" == true ]]; then
      setup_colors
      cmd_version_check
    else
      print -r -- "grove version $VERSION"
    fi
    exit 0
  fi
}

main() {
  load_config
  validate_max_parallel  # Validate GROVE_MAX_PARALLEL after loading config
  parse_flags "$@"
  setup_colors

  # Cache timestamp for this command execution
  _cache_now

  set -- "${REMAINING_ARGS[@]}"

  local cmd="${1:-}"
  shift || true

  # Handle interactive mode for add command
  if [[ "$INTERACTIVE" == true ]]; then
    if [[ -z "$cmd" || "$cmd" == "add" ]]; then
      interactive_add "$@"
      return $?
    fi
  fi

  case "$cmd" in
    add)          cmd_add "$@" ;;
    rm)           cmd_rm "$@" ;;
    move)         cmd_move "$@" ;;
    ls)           cmd_ls "$@" ;;
    status)       cmd_status "$@" ;;
    pull)         cmd_pull "$@" ;;
    pull-all)     cmd_pull_all "$@" ;;
    sync)         cmd_sync "$@" ;;
    clone)        cmd_clone "$@" ;;
    code)         cmd_code "$@" ;;
    open)         cmd_open "$@" ;;
    cd)           cmd_cd "$@" ;;
    exec)         cmd_exec "$@" ;;
    prune)        cmd_prune "$@" ;;
    repos)        cmd_repos "$@" ;;
    templates)    cmd_templates "$@" ;;
    doctor)       cmd_doctor "$@" ;;
    cleanup-herd) cmd_cleanup_herd "$@" ;;
    unlock)       cmd_unlock "$@" ;;
    fresh)        cmd_fresh "$@" ;;
    restructure)  cmd_restructure "$@" ;;
    build-all)    cmd_build_all "$@" ;;
    exec-all)     cmd_exec_all "$@" ;;
    repair)       cmd_repair "$@" ;;
    switch)       cmd_switch "$@" ;;
    tinker)       cmd_tinker "$@" ;;
    log)          cmd_log "$@" ;;
    diff)         cmd_diff "$@" ;;
    summary)      cmd_summary "$@" ;;
    changes)      cmd_changes "$@" ;;
    report)       cmd_report "$@" ;;
    health)       cmd_health "$@" ;;
    branches)     cmd_branches "$@" ;;
    info)         cmd_info "$@" ;;
    recent)       cmd_recent "$@" ;;
    clean)        cmd_clean "$@" ;;
    alias)        cmd_alias "$@" ;;
    upgrade)      cmd_upgrade "$@" ;;
    dashboard)    cmd_dashboard "$@" ;;
    setup)        cmd_setup "$@" ;;
    config)       cmd_config "$@" ;;
    group)        cmd_group "$@" ;;
    share-deps)   cmd_share_deps "$@" ;;
    "")           usage ;;
    *)            die "Unknown command: $cmd (try: grove --help)" ;;
  esac
}

main "$@"
