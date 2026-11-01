#!/usr/bin/env bash
# Does the shell config survive a machine that has only what the repo installs?
#
#   ./scripts/check-bare-shell.sh             # test the working tree
#   ./scripts/check-bare-shell.sh --rev HEAD  # test a committed revision
#
# Builds a throwaway $HOME that contains the managed zsh files plus the two
# things bootstrap.sh installs (Oh My Zsh and powerlevel10k) and nothing else:
# no Rust, no nvm, no Docker, no Herd, no ~/.opencode. Then it starts an
# interactive zsh and fails if any error reaches the terminal.
#
# This is the test that would have caught the repo sourcing ~/.cargo/env
# unconditionally: on a bare Mac that is the first line of output, not an error
# message buried in a log.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REV=""
FAILURES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rev) REV="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'check-bare-shell: unknown option %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; RED=""; DIM=""; BOLD=""; RESET=""
fi
pass() { printf '  %spass%s  %-24s %s%s%s\n' "$GREEN" "$RESET" "$1" "$DIM" "${2:-}" "$RESET"; }
fail() { printf '  %sFAIL%s  %-24s %s\n' "$RED" "$RESET" "$1" "${2:-}"; FAILURES=$((FAILURES + 1)); }

printf '\n%sbare-mac shell%s  %s%s%s\n\n' "$BOLD" "$RESET" \
  "${REV:-working tree}" "$DIM" "$RESET"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bare-shell.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Managed files, from the working tree or from a revision.
extract() { # chezmoi-source-name target-name
  if [[ -n "$REV" ]]; then
    git -C "$ROOT" show "$REV:$1" > "$TMP/$2" 2>/dev/null || return 1
  else
    cp "$ROOT/$1" "$TMP/$2" || return 1
  fi
}

# Required by the repo: the shell framework bootstrap.sh installs.
if [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]] \
   && [[ -f "$HOME/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
  ln -s "$HOME/.oh-my-zsh" "$TMP/.oh-my-zsh"
  pass "framework staged" "oh-my-zsh + powerlevel10k linked in"
else
  fail "framework staged" "run bootstrap.sh first"
fi

for pair in dot_zshenv:.zshenv dot_zshrc:.zshrc dot_p10k.zsh:.p10k.zsh; do
  if ! extract "${pair%%:*}" "${pair##*:}"; then
    fail "managed files" "cannot read ${pair%%:*}"
  fi
done

# A bare Mac: system path plus Homebrew, and no optional toolchains in $HOME.
MIN_PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
OUT="$TMP/typescript"

env -i \
  HOME="$TMP" \
  PATH="$MIN_PATH" \
  TERM="xterm-256color" \
  LANG="en_US.UTF-8" \
  SHELL="/bin/zsh" \
  script -q "$OUT" zsh -i -c 'print -r -- SHELL_OK' >/dev/null 2>&1

if grep -q 'SHELL_OK' "$OUT" 2>/dev/null; then
  pass "shell starts" "interactive zsh reached the end"
else
  fail "shell starts" "interactive zsh did not run to completion"
fi

ERRORS="$(grep -aE 'command not found|no such file or directory|parse error|bad substitution|permission denied|unknown file attribute' \
  "$OUT" 2>/dev/null | sed 's/^/        /' | head -8)"
if [[ -z "$ERRORS" ]]; then
  pass "no errors" "stderr clean with optional tools absent"
else
  fail "no errors" "the shell printed errors on a bare machine"
  printf '%s\n' "$ERRORS"
fi

# The optional tools must be absent from this $HOME, or the test proves nothing.
STRAY=""
for path in .cargo .nvm .docker .opencode "Library/Application Support/Herd"; do
  [[ -e "$TMP/$path" ]] && STRAY="$STRAY $path"
done
if [[ -z "$STRAY" ]]; then
  pass "environment bare" "no Rust, nvm, Docker, Herd or ~/.opencode"
else
  fail "environment bare" "unexpected in test home:$STRAY"
fi

printf '\n'
if (( FAILURES == 0 )); then
  printf '%s%d failed%s\n\n' "$GREEN" "$FAILURES" "$RESET"; exit 0
else
  printf '%s%d failed%s\n\n' "$RED" "$FAILURES" "$RESET"; exit 1
fi
