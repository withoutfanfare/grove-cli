#!/usr/bin/env zsh
# 07-templates.sh - Template loading and listing

# validate_template_name — Validate template name format (security: no path traversal)
validate_template_name() {
  local name="$1"

  validate_identifier_common "$name" "template"

  # Block slashes and backslashes (templates are single files, no paths)
  if [[ "$name" == *"/"* || "$name" == *"\\"* ]]; then
    error_exit "INVALID_INPUT" "Invalid template name: '$name' (path separators not allowed)" 2
  fi

  # Only allow alphanumeric, dash, underscore (stricter than repo/branch names)
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error_exit "INVALID_INPUT" "Invalid template name: '$name' (only alphanumeric, dash, underscore allowed)" 2
  fi
}

# extract_template_desc — Read TEMPLATE_DESC value from a template config file
extract_template_desc() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == TEMPLATE_DESC=* ]]; then
      local desc="${line#TEMPLATE_DESC=}"
      desc="${desc#\"}"
      desc="${desc%\"}"
      desc="${desc#\'}"
      desc="${desc%\'}"
      print -r -- "$desc"
      return 0
    fi
  done < "$file"
}

# suggest_similar — Find closest matching name for "did you mean?" suggestions
suggest_similar() {
  local input="$1" type="$2"
  shift 2
  local options=("$@")
  local best_match="" best_score=999

  for opt in "${options[@]}"; do
    # Simple similarity: count matching characters at start
    local i=0 score=0
    local input_lower="${input:l}" opt_lower="${opt:l}"

    # Check if input is a prefix
    if [[ "$opt_lower" == "$input_lower"* ]]; then
      score=$((${#opt} - ${#input}))
      if (( score < best_score )); then
        best_score=$score
        best_match="$opt"
      fi
      continue
    fi

    # Check if input is a substring
    if [[ "$opt_lower" == *"$input_lower"* ]]; then
      score=$((${#opt} - ${#input} + 5))
      if (( score < best_score )); then
        best_score=$score
        best_match="$opt"
      fi
      continue
    fi

    # Levenshtein-like: count character differences (simplified)
    local len1=${#input_lower} len2=${#opt_lower}
    local max_len=$(( len1 > len2 ? len1 : len2 ))
    local matching=0
    for (( i=0; i < max_len; i++ )); do
      # Use safe assignment instead of ((matching++)) which exits with set -e when matching=0
      if [[ "${input_lower:$i:1}" == "${opt_lower:$i:1}" ]]; then
        matching=$((matching + 1))
      fi
    done
    score=$((max_len - matching))
    if (( score < best_score && score < max_len / 2 )); then
      best_score=$score
      best_match="$opt"
    fi
  done

  # Only suggest if reasonably close (within half the length)
  if [[ -n "$best_match" && $best_score -lt ${#input} ]]; then
    print -r -- "$best_match"
  fi
}

# get_template_names — Return space-separated list of available template names
get_template_names() {
  local templates=()
  if [[ -d "$GROVE_TEMPLATES_DIR" ]]; then
    for f in "$GROVE_TEMPLATES_DIR"/*.conf(N); do
      templates+=("${f:t:r}")
    done
  fi
  print -r -- "${templates[@]}"
}

# load_template — Parse and apply a template file, exporting GROVE_SKIP_* variables
load_template() {
  local template_name="$1"

  # Validate template name first (security: prevent path traversal)
  validate_template_name "$template_name"

  local template_file="$GROVE_TEMPLATES_DIR/${template_name}.conf"

  # Check if template exists
  if [[ ! -f "$template_file" ]]; then
    local available_templates
    available_templates=($(get_template_names))

    local suggestion=""
    if (( ${#available_templates[@]} > 0 )); then
      suggestion="$(suggest_similar "$template_name" "template" "${available_templates[@]}")"
    fi

    # For JSON output, use simple error message
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      local json_msg="Template not found: '$template_name'"
      [[ -n "$suggestion" ]] && json_msg+=". Did you mean: '$suggestion'?"
      error_exit "REPO_NOT_FOUND" "$json_msg" 3
    fi

    # For text output, use formatted message
    local error_msg="Template not found: ${C_CYAN}$template_name${C_RESET}"
    if [[ -n "$suggestion" ]]; then
      error_msg+="\n\n  ${C_YELLOW}Did you mean:${C_RESET} ${C_GREEN}$suggestion${C_RESET}?"
    fi
    error_msg+="\n\n${C_DIM}Available templates:${C_RESET}\n$(list_templates 2>&1)"
    error_msg+="\n\n${C_DIM}Run 'grove templates' to see all templates${C_RESET}"

    die "$error_msg"
  fi

  # Parse template file (only allow GROVE_SKIP_* and TEMPLATE_DESC)
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" || "$key" =~ ^[[:space:]]*$ ]] && continue

    # Trim whitespace from key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    # Remove quotes and trailing comments from value
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    value="${value%%#*}"
    value="${value%"${value##*[![:space:]]}"}"

    # Only allow GROVE_SKIP_* variables with true/false values (security)
    case "$key" in
      GROVE_SKIP_*)
        # Security: Only allow true/false values to prevent command injection
        if [[ "$value" != "true" && "$value" != "false" ]]; then
          warn "Invalid value for $key: '$value' (must be true or false) - skipping"
          continue
        fi
        export "$key"="$value"
        ;;
      TEMPLATE_DESC) ;; # Ignore, used for display only
      *) ;; # Ignore other variables (security)
    esac
  done < "$template_file"

  dim "  Applied template: $template_name"
}

# list_templates — Display available templates with descriptions
list_templates() {
  local templates_found=false

  if [[ -d "$GROVE_TEMPLATES_DIR" ]]; then
    for f in "$GROVE_TEMPLATES_DIR"/*.conf(N); do
      templates_found=true
      local name="${f:t:r}"  # Remove path and .conf extension
      local desc=""

      # Extract TEMPLATE_DESC if present
      desc="$(extract_template_desc "$f")"

      if [[ -n "$desc" ]]; then
        print -r -- "  $name - $desc"
      else
        print -r -- "  $name"
      fi
    done
  fi

  if [[ "$templates_found" != true ]]; then
    print -r -- "  (no templates found)"
    print -r -- ""
    print -r -- "  Create templates in: $GROVE_TEMPLATES_DIR/"
    print -r -- "  Example: $GROVE_TEMPLATES_DIR/laravel.conf"
  fi
}

# json_escape — Escape a string for safe JSON embedding (sets REPLY)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"       # Backslash must be first
  s="${s//\"/\\\"}"       # Double quote
  s="${s//$'\n'/\\n}"     # Newline
  s="${s//$'\t'/\\t}"     # Tab
  s="${s//$'\r'/\\r}"     # Carriage return
  s="${s//$'\f'/\\f}"     # Form feed
  s="${s//$'\b'/\\b}"     # Backspace
  REPLY="$s"
}

# Cached JSON formatter detection (set on first use)
typeset -g _GROVE_JSON_FORMATTER=""

# format_json — Pretty-print JSON with colours and indentation (uses jq/python3/fallback)
format_json() {
  local json="$1"

  if [[ "$PRETTY_JSON" != true ]]; then
    print -r -- "$json"
    return
  fi

  # Detect formatter once on first use
  if [[ -z "$_GROVE_JSON_FORMATTER" ]]; then
    if command -v jq >/dev/null 2>&1; then
      _GROVE_JSON_FORMATTER="jq"
    elif command -v python3 >/dev/null 2>&1; then
      _GROVE_JSON_FORMATTER="python3"
    else
      _GROVE_JSON_FORMATTER="none"
    fi
  fi

  # Use cached formatter choice
  local result="$json"
  local formatted=""

  if [[ "$_GROVE_JSON_FORMATTER" == "jq" ]]; then
    if formatted="$(print -r -- "$json" | jq . 2>/dev/null)"; then
      result="$formatted"
    fi
  elif [[ "$_GROVE_JSON_FORMATTER" == "python3" ]]; then
    if formatted="$(print -r -- "$json" | python3 -m json.tool 2>/dev/null)"; then
      result="$formatted"
    fi
  else
    # Fallback: simple string replacements for basic formatting
    result="${result//\[/$'\n['}"
    result="${result//\{/$'\n  {'}"
    result="${result//\}/$'}\n'}"
    result="${result//\],/$'],\n'}"
    result="${result//\}, /'},\n  '}"
  fi

  # Apply colours if terminal supports it
  if [[ -t 1 ]]; then
    # Colour keys (words before colons)
    result="$(print -r -- "$result" | sed -E "s/\"([^\"]+)\":/\"${C_CYAN}\1${C_RESET}\":/g")"
    # Colour string values
    result="$(print -r -- "$result" | sed -E "s/: \"([^\"]*)\"/: \"${C_GREEN}\1${C_RESET}\"/g")"
    # Colour booleans
    result="${result//: true/: ${C_MAGENTA}true${C_RESET}}"
    result="${result//: false/: ${C_MAGENTA}false${C_RESET}}"
    # Colour numbers (simple approach)
    result="$(print -r -- "$result" | sed -E "s/: ([0-9]+)([,}])/: ${C_YELLOW}\1${C_RESET}\2/g")"
  fi

  print -r -- "$result"
}
