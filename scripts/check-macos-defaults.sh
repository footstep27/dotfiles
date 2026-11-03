#!/usr/bin/env bash
# Does the macOS defaults manifest, typed diff, apply and revert behave?
#
#   ./scripts/check-macos-defaults.sh
#
# Runs against a throwaway $HOME and a fake `defaults` command. No real
# preferences are read or written.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; RED=""; DIM=""; BOLD=""; RESET=""
fi
pass() { printf '  %spass%s  %-24s %s%s%s\n' "$GREEN" "$RESET" "$1" "$DIM" "${2:-}" "$RESET"; }
fail() { printf '  %sFAIL%s  %-24s %s\n' "$RED" "$RESET" "$1" "${2:-}"; FAILURES=$((FAILURES + 1)); }

printf '\n%smacOS defaults%s\n\n' "$BOLD" "$RESET"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-macos-defaults.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

export HOME="$TMP"
export DOTFILES_ROOT="$ROOT"
export DOTFILES_STATE_DIR="$TMP/state"
export MACOS_RESTART=0
mkdir -p "$TMP/bin"

cat > "$TMP/bin/defaults" <<'FAKE_DEFAULTS'
#!/usr/bin/env bash
set -u
store="$HOME/.fake-defaults"
case "${1:-}" in
  read)
    file="$store/${2:-}/${3:-}"
    [[ -f "$file" ]] || exit 1
    cat "$file"
    ;;
  write)
    domain="${2:-}"; key="${3:-}"; type="${4#-}"; value="${5:-}"
    mkdir -p "$store/$domain"
    case "$type" in
      bool)
        case "$value" in
          true|TRUE|YES|yes|1) value=1 ;;
          *) value=0 ;;
        esac
        ;;
    esac
    printf '%s' "$value" > "$store/$domain/$key"
    ;;
  delete)
    rm -f "$store/${2:-}/${3:-}"
    ;;
  *)
    exit 2
    ;;
esac
FAKE_DEFAULTS
chmod +x "$TMP/bin/defaults"
export PATH="$TMP/bin:$PATH"

# shellcheck source=lib-macos.sh
source "$ROOT/scripts/lib-macos.sh"

fake_set() { defaults write "$1" "$2" -"$3" "$4"; }
fake_get() { defaults read "$1" "$2" 2>/dev/null; }

if macos_load_manifest && (( MACOS_N > 30 )); then
  pass "manifest" "$MACOS_N keys"
else
  fail "manifest" "${MACOS_CONF_ERRORS:-no keys}"
fi

fake_set NSGlobalDomain KeyRepeat int 1
macos_apply_groups $'keyboard\n' 0
if [[ "$(fake_get NSGlobalDomain KeyRepeat)" == "2" ]] \
   && grep -Fq $'NSGlobalDomain\tKeyRepeat\tint\t1' "$DOTFILES_MACOS_BEFORE"; then
  pass "apply" "value written and before-value kept"
else
  fail "apply" "value or before-value wrong"
fi
if printf '%s' "$MACOS_REPORT" | grep -Fq 'KeyRepeat: 1 -> 2'; then
  pass "report" "old and new values shown"
else
  fail "report" "transition missing"
fi

BEFORE_LINES="$(wc -l < "$DOTFILES_MACOS_BEFORE" | tr -d ' ')"
macos_apply_groups $'keyboard\n' 0
AFTER_LINES="$(wc -l < "$DOTFILES_MACOS_BEFORE" | tr -d ' ')"
if printf '%s' "$MACOS_REPORT" | grep -Fq 'already set' && [[ "$BEFORE_LINES" == "$AFTER_LINES" ]]; then
  pass "idempotent" "unchanged keys skipped"
else
  fail "idempotent" "rewrote or re-recorded unchanged keys"
fi

fake_set NSGlobalDomain KeyRepeat int 3
macos_apply_groups $'keyboard\n' 0
if grep -Fq $'NSGlobalDomain\tKeyRepeat\tint\t1' "$DOTFILES_MACOS_BEFORE"; then
  pass "before-value" "original survives later changes"
else
  fail "before-value" "original was overwritten"
fi

fake_set NSGlobalDomain KeyRepeat int 3
macos_check_groups $'keyboard\n'
if [[ -n "$MACOS_DRIFT" ]] && printf '%s' "$MACOS_DRIFT" | grep -q 'KeyRepeat'; then
  pass "drift" "changed key detected"
else
  fail "drift" "changed key not detected"
fi

macos_apply_groups $'keyboard\n' 0
macos_check_groups $'keyboard\n'
if [[ -z "$MACOS_DRIFT" ]]; then
  pass "verify" "applied group matches"
else
  fail "verify" "drift remains after apply"
fi

macos_revert 0
if [[ "$(fake_get NSGlobalDomain KeyRepeat)" == "1" ]] && [[ ! -f "$DOTFILES_MACOS_BEFORE" ]]; then
  pass "revert" "previous value restored"
else
  fail "revert" "value not restored or before-file kept"
fi

macos_revert 0
if printf '%s' "$MACOS_REPORT" | grep -Fq 'nothing to revert'; then
  pass "revert idempotent" "second run is a no-op"
else
  fail "revert idempotent" "second run changed something"
fi

defaults delete NSGlobalDomain KeyRepeat
macos_apply_groups $'keyboard\n' 0
if grep -Fq $'NSGlobalDomain\tKeyRepeat\tint\t__unset__' "$DOTFILES_MACOS_BEFORE"; then
  pass "unset value" "recorded for deletion"
else
  fail "unset value" "missing __unset__ record"
fi
macos_revert 0
if ! defaults read NSGlobalDomain KeyRepeat >/dev/null 2>&1; then
  pass "unset revert" "key removed again"
else
  fail "unset revert" "key still present"
fi

printf 'keyboard\tNSGlobalDomain\tKeyRepeat\tbogus\t2\n' > "$TMP/bad.tsv"
DOTFILES_MACOS_MANIFEST="$TMP/bad.tsv"
if ! macos_load_manifest; then
  pass "invalid manifest" "unknown type rejected"
else
  fail "invalid manifest" "unknown type accepted"
fi

printf '\n'
if (( FAILURES == 0 )); then
  printf '%s%d failed%s\n\n' "$GREEN" "$FAILURES" "$RESET"; exit 0
else
  printf '%s%d failed%s\n\n' "$RED" "$FAILURES" "$RESET"; exit 1
fi
