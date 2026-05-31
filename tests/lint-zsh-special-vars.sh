#!/usr/bin/env bash
# Guard against shadowing zsh special parameters with `local`/`typeset`/`declare`.
#
# In zsh, names like `path`, `status`, `prompt`, `options`, `cdpath`, `fpath`,
# `pipestatus`, `commands`, `functions`, `aliases` and `dirstack` are SPECIAL
# parameters. Declaring e.g. `local path=...` inside a function clobbers $PATH
# for that scope, so external commands silently fail (`command not found`).
# The bash test-mirrors cannot catch this because these names are not special
# in bash — hence this static source lint.
#
# Usage: tests/lint-zsh-special-vars.sh [lib-dir]
# Exits non-zero (and prints offenders) if any special parameter is shadowed.

set -u
lib_dir="${1:-$(cd "$(dirname "$0")/../lib" && pwd)}"

# zsh special parameters that are dangerous to shadow with a local declaration.
specials=" path PATH cdpath CDPATH fpath FPATH manpath MANPATH module_path status pipestatus prompt PROMPT PROMPT2 RPROMPT PS1 PS2 PS3 PS4 argv commands functions aliases dirstack DIRSTACK mailpath MAILPATH psvar watch options signals fignore histchars nullcmd readnullcmd "

found=0
while IFS= read -r file; do
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Only consider declaration lines.
    case "$line" in
      *local\ *|*local$'\t'*|*typeset\ *|*declare\ *) : ;;
      *) continue ;;
    esac
    [[ "$line" =~ ^[[:space:]]*(local|typeset|declare)([[:space:]]|$) ]] || continue

    # Strip everything that could contain a special name as DATA rather than as
    # a declared variable: quoted strings, $(...) / ${...} / $var expansions,
    # then trailing comments. What remains is `local FLAGS name name=… name[…`.
    stripped="$line"
    stripped="$(printf '%s' "$stripped" | sed -E '
      s/"[^"]*"/ /g;        # double-quoted strings
      s/'"'"'[^'"'"']*'"'"'/ /g;   # single-quoted strings
      s/\$\([^)]*\)/ /g;    # $( ... )
      s/\$\{[^}]*\}/ /g;    # ${ ... }
      s/\$[A-Za-z_][A-Za-z0-9_]*/ /g; # $var
      s/#.*//;              # trailing comment
    ')"

    # Tokenise; the declared names are tokens before any = or [ , skipping the
    # leading keyword and any -flags. Word-splitting on $stripped is intentional.
    # shellcheck disable=SC2086
    for tok in $stripped; do
      case "$tok" in
        local|typeset|declare) continue ;;
        -*) continue ;;
      esac
      name="${tok%%=*}"; name="${name%%\[*}"; name="${name%%;*}"
      [[ -n "$name" ]] || continue
      if [[ "$specials" == *" $name "* ]]; then
        echo "  $file:$lineno: declares special zsh parameter '\$$name' -> ${line#"${line%%[![:space:]]*}"}"
        found=1
      fi
    done
  done < "$file"
done < <(find "$lib_dir" -name '*.sh' -type f | sort)

if [[ $found -eq 0 ]]; then
  echo "OK: no zsh special-parameter shadowing in $lib_dir"
  exit 0
fi
exit 1
