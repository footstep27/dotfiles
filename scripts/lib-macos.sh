# shellcheck shell=bash
# Shared model for the optional macOS preference groups.
#
# scripts/macos-defaults.tsv declares one key per line:
#
#   group<TAB>domain<TAB>key<TAB>type<TAB>value
#
# bootstrap.sh applies the groups selected in the inventory, verify.sh reads
# them back, and `bootstrap.sh --revert-macos` restores the values recorded
# before the first change. Nothing here prints: operations append
# `level<TAB>message` lines to MACOS_REPORT, and verification fills MACOS_DRIFT.

DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.local/state/dotfiles}"
DOTFILES_MACOS_MANIFEST="${DOTFILES_MACOS_MANIFEST:-$DOTFILES_ROOT/scripts/macos-defaults.tsv}"
DOTFILES_MACOS_BEFORE="${DOTFILES_MACOS_BEFORE:-$DOTFILES_STATE_DIR/macos-defaults.before}"

# Tests and dry runs set this to 0 so killall never touches a real GUI.
MACOS_RESTART="${MACOS_RESTART:-1}"

MACOS_REPORT=""
MACOS_DRIFT=""
MACOS_CONF_ERRORS=""

MACOS_N=0
MACOS_GROUP=(); MACOS_DOMAIN=(); MACOS_KEY=(); MACOS_TYPE=(); MACOS_VALUE=()

macos_report() { # level message
  MACOS_REPORT="$MACOS_REPORT$1"$'\t'"$2"$'\n'
}

macos_load_manifest() {
  MACOS_N=0
  MACOS_GROUP=(); MACOS_DOMAIN=(); MACOS_KEY=(); MACOS_TYPE=(); MACOS_VALUE=()
  MACOS_CONF_ERRORS=""

  if [[ ! -f "$DOTFILES_MACOS_MANIFEST" ]]; then
    MACOS_CONF_ERRORS="missing $DOTFILES_MACOS_MANIFEST"
    return 1
  fi

  local line group domain key type value
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ""|\#*) continue ;;
    esac

    group=""; domain=""; key=""; type=""; value=""
    IFS=$'\t' read -r group domain key type value <<< "$line"
    if [[ -z "$group" || -z "$domain" || -z "$key" || -z "$type" || -z "$value" ]]; then
      MACOS_CONF_ERRORS="$MACOS_CONF_ERRORS$line"$'\n'
      continue
    fi
    case "$type" in
      bool|int|float|string) ;;
      *)
        MACOS_CONF_ERRORS="$MACOS_CONF_ERRORS$line"$'\n'
        continue
        ;;
    esac

    MACOS_GROUP[MACOS_N]="$group"
    MACOS_DOMAIN[MACOS_N]="$domain"
    MACOS_KEY[MACOS_N]="$key"
    MACOS_TYPE[MACOS_N]="$type"
    MACOS_VALUE[MACOS_N]="$value"
    MACOS_N=$((MACOS_N + 1))
  done < "$DOTFILES_MACOS_MANIFEST"

  if (( MACOS_N == 0 )); then
    MACOS_CONF_ERRORS="${MACOS_CONF_ERRORS}no keys declared"$'\n'
  fi
  [[ -z "$MACOS_CONF_ERRORS" ]]
}

macos_expand_value() {
  local value="$1"
  value="${value//\$\{HOME\}/$HOME}"
  value="${value//\$HOME/$HOME}"
  printf '%s' "$value"
}

macos_current() { # domain key
  local current
  if current="$(defaults read "$1" "$2" 2>/dev/null)"; then
    printf '%s' "$current"
  else
    printf '%s' "__unset__"
  fi
}

# Sandboxed apps keep their preferences inside ~/Library/Containers/<domain>.
# macOS blocks other processes from that directory unless the terminal has Full
# Disk Access; detect it so we can skip the group with one clear message
# instead of a wall of `defaults` errors.
macos_domain_accessible() { # domain
  local domain="$1" root="$HOME/Library/Containers/$1"
  [[ -d "$root" ]] || return 0
  [[ -w "$root/Data/Library/Preferences" ]]
}

macos_normalize() { # type value
  case "$1" in
    bool)
      case "$2" in
        1|true|TRUE|YES|yes) printf '1' ;;
        0|false|FALSE|NO|no) printf '0' ;;
        *) printf '%s' "$2" ;;
      esac
      ;;
    *) printf '%s' "$2" ;;
  esac
}

macos_equal() { # type current desired
  [[ "$2" == "__unset__" ]] && return 1
  case "$1" in
    bool)
      [[ "$(macos_normalize bool "$2")" == "$(macos_normalize bool "$3")" ]]
      ;;
    int)
      [[ "$2" =~ ^-?[0-9]+$ && "$3" =~ ^-?[0-9]+$ ]] || return 1
      (( $2 == $3 ))
      ;;
    float)
      awk -v a="$2" -v b="$3" 'BEGIN { exit ((a + 0) == (b + 0)) ? 0 : 1 }'
      ;;
    *)
      [[ "$2" == "$3" ]]
      ;;
  esac
}

macos_before_has() { # domain key
  [[ -f "$DOTFILES_MACOS_BEFORE" ]] || return 1
  awk -F'\t' -v d="$1" -v k="$2" \
    '$1 !~ /^#/ && $2 == d && $3 == k { found = 1 } END { exit(found ? 0 : 1) }' \
    "$DOTFILES_MACOS_BEFORE"
}

macos_record_before() { # group domain key type current
  local group="$1" domain="$2" key="$3" type="$4" current="$5"
  mkdir -p "$(dirname "$DOTFILES_MACOS_BEFORE")"
  [[ -f "$DOTFILES_MACOS_BEFORE" ]] \
    || printf '# group\tdomain\tkey\ttype\tvalue\n' > "$DOTFILES_MACOS_BEFORE"
  macos_before_has "$domain" "$key" && return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$group" "$domain" "$key" "$type" "$current" \
    >> "$DOTFILES_MACOS_BEFORE"
}

macos_write() { # type domain key value
  case "$1" in
    bool)   defaults write "$2" "$3" -bool "$4" 2>/dev/null ;;
    int)    defaults write "$2" "$3" -int "$4" 2>/dev/null ;;
    float)  defaults write "$2" "$3" -float "$4" 2>/dev/null ;;
    string) defaults write "$2" "$3" -string "$4" 2>/dev/null ;;
    *)      return 1 ;;
  esac
}

macos_restart_group() { # group
  (( MACOS_RESTART )) || return 0
  case "$1" in
    finder)    killall Finder 2>/dev/null || true ;;
    screenshots) killall SystemUIServer 2>/dev/null || true ;;
    dock)      killall Dock 2>/dev/null || true ;;
    menubar)   killall SystemUIServer 2>/dev/null || true ;;
  esac
}

macos_apply_group() { # group dry
  local group="$1" dry="$2" i=0 changed=0 unchanged=0 total=0 current desired blocked="" domain
  if [[ "$group" == "screenshots" ]] && (( ! dry )); then
    mkdir -p "$HOME/Pictures/Screenshots" || {
      macos_report warn "screenshots: could not create $HOME/Pictures/Screenshots"
    }
  fi

  while (( i < MACOS_N )); do
    if [[ "${MACOS_GROUP[$i]}" == "$group" ]] && ! macos_domain_accessible "${MACOS_DOMAIN[$i]}"; then
      domain="${MACOS_DOMAIN[$i]}"
      case " $blocked " in
        *" $domain "*) ;;
        *)
          if [[ -z "$blocked" ]]; then blocked="$domain"; else blocked="$blocked $domain"; fi
          ;;
      esac
    fi
    i=$((i + 1))
  done
  if [[ -n "$blocked" ]]; then
    macos_report warn "$group: macOS protects $blocked — grant Full Disk Access to your terminal or set these manually"
    return 0
  fi

  i=0
  while (( i < MACOS_N )); do
    if [[ "${MACOS_GROUP[$i]}" == "$group" ]]; then
      total=$((total + 1))
      current="$(macos_current "${MACOS_DOMAIN[$i]}" "${MACOS_KEY[$i]}")"
      desired="$(macos_expand_value "${MACOS_VALUE[$i]}")"
      if macos_equal "${MACOS_TYPE[$i]}" "$current" "$desired"; then
        unchanged=$((unchanged + 1))
      else
        changed=$((changed + 1))
        if (( dry )); then
          macos_report info "$group: ${MACOS_DOMAIN[$i]} ${MACOS_KEY[$i]}: $current -> $desired"
        else
          macos_record_before "$group" "${MACOS_DOMAIN[$i]}" "${MACOS_KEY[$i]}" \
            "${MACOS_TYPE[$i]}" "$current"
          if macos_write "${MACOS_TYPE[$i]}" "${MACOS_DOMAIN[$i]}" "${MACOS_KEY[$i]}" "$desired"; then
            macos_report info "$group: ${MACOS_DOMAIN[$i]} ${MACOS_KEY[$i]}: $current -> $desired"
          else
            macos_report warn "$group: could not set ${MACOS_DOMAIN[$i]} ${MACOS_KEY[$i]}"
          fi
        fi
      fi
    fi
    i=$((i + 1))
  done

  if (( total == 0 )); then
    macos_report warn "$group: no keys declared"
  elif (( changed > 0 )); then
    if (( ! dry )); then
      macos_restart_group "$group"
      if [[ "$group" == "apps" ]]; then
        macos_report info "apps: relaunch TextEdit, Activity Monitor, Disk Utility, Safari and Terminal to apply"
      fi
    fi
    macos_report info "$group: $changed changed, $unchanged already set"
  elif (( unchanged > 0 )); then
    macos_report info "$group: $unchanged already set"
  fi
}

macos_apply_groups() { # groups dry
  local groups="$1" dry="$2" group
  MACOS_REPORT=""
  while IFS= read -r group; do
    [[ -z "$group" ]] && continue
    macos_apply_group "$group" "$dry"
  done <<< "$groups"
}

macos_check_groups() { # groups
  local groups="$1" group i=0 total=0 current desired blocked="" domain
  MACOS_DRIFT=""
  while IFS= read -r group; do
    [[ -z "$group" ]] && continue
    total=0
    blocked=""
    i=0
    while (( i < MACOS_N )); do
      if [[ "${MACOS_GROUP[$i]}" == "$group" ]]; then
        total=$((total + 1))
        if ! macos_domain_accessible "${MACOS_DOMAIN[$i]}"; then
          domain="${MACOS_DOMAIN[$i]}"
          case " $blocked " in
            *" $domain "*) ;;
            *)
              if [[ -z "$blocked" ]]; then blocked="$domain"; else blocked="$blocked $domain"; fi
              ;;
          esac
          i=$((i + 1))
          continue
        fi
        current="$(macos_current "${MACOS_DOMAIN[$i]}" "${MACOS_KEY[$i]}")"
        desired="$(macos_expand_value "${MACOS_VALUE[$i]}")"
        if ! macos_equal "${MACOS_TYPE[$i]}" "$current" "$desired"; then
          MACOS_DRIFT="$MACOS_DRIFT$group ${MACOS_DOMAIN[$i]} ${MACOS_KEY[$i]}: $current != $desired"$'\n'
        fi
      fi
      i=$((i + 1))
    done
    if [[ -n "$blocked" ]]; then
      MACOS_DRIFT="$MACOS_DRIFT$group: requires Full Disk Access for $blocked"$'\n'
    fi
    if (( total == 0 )); then
      MACOS_DRIFT="$MACOS_DRIFT$group: no keys declared"$'\n'
    fi
  done <<< "$groups"
}

macos_revert() { # dry
  local dry="$1" group domain key type value groups="" failed=0
  MACOS_REPORT=""

  if [[ ! -f "$DOTFILES_MACOS_BEFORE" ]]; then
    macos_report info "nothing to revert"
    return 0
  fi

  while IFS=$'\t' read -r group domain key type value; do
    case "$group" in
      ""|\#*) continue ;;
    esac
    case "$groups" in
      *$'\n'"$group"$'\n'*) ;;
      *) groups="$groups$group"$'\n' ;;
    esac

    if (( dry )); then
      macos_report info "would restore $group: $domain $key -> $value"
      continue
    fi

    if [[ "$value" == "__unset__" ]]; then
      defaults delete "$domain" "$key" 2>/dev/null || true
      macos_report info "deleted $group: $domain $key"
    elif macos_write "$type" "$domain" "$key" "$value"; then
      macos_report info "restored $group: $domain $key -> $value"
    else
      macos_report warn "could not restore $group: $domain $key"
      failed=1
    fi
  done < "$DOTFILES_MACOS_BEFORE"

  if (( ! dry )); then
    if (( failed == 0 )); then
      rm -f "$DOTFILES_MACOS_BEFORE"
    else
      macos_report warn "some values could not be restored; kept $DOTFILES_MACOS_BEFORE"
    fi
    while IFS= read -r group; do
      [[ -z "$group" ]] && continue
      macos_restart_group "$group"
    done <<< "$groups"
  fi
}
