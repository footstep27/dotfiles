#!/usr/bin/env bash
# Is this machine a healthy instance of the setup?
#
#   ./scripts/verify.sh
#
# Prints one row per check. Exit 0 when nothing failed (warnings are allowed),
# non-zero when any check failed. Checks assert observable behaviour — a config
# that parses, a font that resolves, a shell that loads — not file contents.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
  DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; RED=""; YELLOW=""; DIM=""; BOLD=""; RESET=""
fi

pass() { printf '  %spass%s  %-28s %s%s%s\n' "$GREEN" "$RESET" "$1" "$DIM" "${2:-}" "$RESET"; }
fail() { printf '  %sFAIL%s  %-28s %s\n' "$RED" "$RESET" "$1" "${2:-}"; FAILURES=$((FAILURES + 1)); }
warn() { printf '  %swarn%s  %-28s %s\n' "$YELLOW" "$RESET" "$1" "${2:-}"; }

printf '\n%sverify%s  %s\n\n' "$BOLD" "$RESET" "$ROOT"

# ---------------------------------------------------------------- Ghostty app
GHOSTTY_BIN=""
for candidate in /Applications/Ghostty.app/Contents/MacOS/ghostty \
                 "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"; do
  if [[ -x "$candidate" ]]; then GHOSTTY_BIN="$candidate"; break; fi
done
if [[ -n "$GHOSTTY_BIN" ]]; then
  pass "ghostty installed" "$("$GHOSTTY_BIN" +version 2>/dev/null | head -1)"
else
  fail "ghostty installed" "not in /Applications — run bootstrap.sh"
fi

# ------------------------------------------------------------- Config parses
if [[ -n "$GHOSTTY_BIN" ]]; then
  CONFIG="$HOME/.config/ghostty/config"
  if [[ ! -f "$CONFIG" ]]; then
    fail "ghostty config" "missing $CONFIG"
  else
    CONFIG_ERRORS="$("$GHOSTTY_BIN" +validate-config --config-file="$CONFIG" 2>&1)"
    if [[ -z "$CONFIG_ERRORS" ]]; then
      pass "ghostty config parses"
    else
      fail "ghostty config parses" "$(printf '%s' "$CONFIG_ERRORS" | head -1)"
    fi
  fi

  # ----------------------------------------------------------- Font fallback
  # 0x61 = 'a' (text face), 0xf07b = nerd font folder glyph (fallback face)
  TEXT_FACE="$("$GHOSTTY_BIN" +show-face --cp=0x61 2>/dev/null | head -1)"
  ICON_FACE="$("$GHOSTTY_BIN" +show-face --cp=0xf07b 2>/dev/null | head -1)"
  if [[ "$TEXT_FACE" == *MonoLisa* ]]; then
    pass "font: text face" "MonoLisa"
  else
    warn "font: text face" "not MonoLisa (licensed font missing?) — see docs/fonts.md"
  fi
  if [[ "$ICON_FACE" == *"Symbols Nerd Font"* ]]; then
    pass "font: icon fallback" "Symbols Nerd Font Mono"
  else
    fail "font: icon fallback" "icons would render as boxes"
  fi
else
  warn "font checks" "skipped, Ghostty not found"
fi

# --------------------------------------------------------------- Shell loads
# A pty is used on purpose: p10k/gitstatus prints a spurious "restart zsh"
# notice when stdin is not a terminal, which is not a real error.
SHELL_ERR="$(script -q /dev/null zsh -i -c true 2>&1 >/dev/null | tr -d '\004' | grep -viE '^$|^OK')"
if [[ -z "$SHELL_ERR" ]]; then
  pass "shell loads" "zsh -i, no errors"
else
  fail "shell loads" "$(printf '%s' "$SHELL_ERR" | head -1)"
fi

# --------------------------------------------------------------- PATH health
DUPES="$(zsh -i -c 'print -l ${(s.:.)PATH}' 2>/dev/null | sort | uniq -d | grep -c . )"
if [[ "$DUPES" == "0" ]]; then
  pass "PATH" "no duplicate entries"
else
  warn "PATH" "$DUPES duplicated entries"
fi

# --------------------------------------------------------------- tmux config
if command -v tmux >/dev/null 2>&1; then
  SOCKET="verify-$$"
  if tmux -L "$SOCKET" new-session -d 2>/dev/null; then
    DEFAULT_TERMINAL="$(tmux -L "$SOCKET" show -g default-terminal 2>/dev/null)"
    tmux -L "$SOCKET" kill-server 2>/dev/null
    if [[ "$DEFAULT_TERMINAL" == *tmux-256color* ]]; then
      pass "tmux config" "$DEFAULT_TERMINAL"
    else
      fail "tmux config" "default-terminal is '$DEFAULT_TERMINAL'"
    fi
  else
    fail "tmux config" "server refused to start"
  fi

  # Plugins: present, and at the ref declared in the config
  MISSING=(); WRONGREF=(); SPECS=0
  while IFS= read -r spec; do
    name="${spec%%#*}"; name="${name##*/}"
    ref="${spec##*#}"
    dir="$HOME/.tmux/plugins/$name"
    SPECS=$((SPECS + 1))
    if [[ ! -d "$dir" ]]; then
      MISSING+=("$name")
      continue
    fi
    actual="$(git -C "$dir" describe --tags --always 2>/dev/null)"
    if [[ "$actual" != "$ref" ]]; then WRONGREF+=("$name@$actual"); fi
  done < <(sed -n "s/^[[:space:]]*set -g @plugin '\(.*\)'.*/\1/p" "$HOME/.tmux.conf")
  if (( SPECS == 0 )); then
    fail "tmux plugins" "no @plugin lines readable from ~/.tmux.conf"
  elif [[ ${#MISSING[@]} -eq 0 && ${#WRONGREF[@]} -eq 0 ]]; then
    pass "tmux plugins" "$SPECS at pinned refs"
  else
    [[ ${#MISSING[@]} -gt 0 ]] && fail "tmux plugins" "missing: ${MISSING[*]}"
    [[ ${#WRONGREF[@]} -gt 0 ]] && fail "tmux plugins" "off-pin: ${WRONGREF[*]}"
  fi
else
  fail "tmux" "not installed"
fi

# ------------------------------------------------------ Terminal capabilities
if infocmp -x xterm-ghostty >/dev/null 2>&1; then
  pass "terminfo" "xterm-ghostty known (tmux-safe)"
else
  warn "terminfo" "xterm-ghostty unknown — launch Ghostty once to install it"
fi

# ------------------------------------------------------------------ Brewfile
if command -v brew >/dev/null 2>&1; then
  if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="$ROOT/Brewfile" >/dev/null 2>&1; then
    pass "required packages" "Brewfile satisfied"
  else
    fail "required packages" "run: brew bundle install --file=$ROOT/Brewfile"
  fi
else
  fail "homebrew" "not installed"
fi

# ------------------------------------------------------------- chezmoi drift
if command -v chezmoi >/dev/null 2>&1; then
  if [[ -z "$(chezmoi diff 2>/dev/null)" ]]; then
    pass "chezmoi" "applied, no drift"
  else
    warn "chezmoi" "local drift — review with: chezmoi diff"
  fi
else
  fail "chezmoi" "not installed"
fi

printf '\n'
if (( FAILURES == 0 )); then
  printf '%s%d failed%s\n\n' "$GREEN" "$FAILURES" "$RESET"
  exit 0
else
  printf '%s%d failed%s\n\n' "$RED" "$FAILURES" "$RESET"
  exit 1
fi
