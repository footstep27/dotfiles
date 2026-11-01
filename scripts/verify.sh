#!/usr/bin/env bash
# Is this machine a healthy instance of the setup?
#
#   ./scripts/verify.sh            # full check, needs the apps installed
#   ./scripts/verify.sh --static   # repo-side only, no Ghostty or tmux needed
#
# Prints one row per check. Exit 0 when nothing failed (warnings are allowed),
# non-zero when any check failed. Checks assert observable behaviour — a config
# that parses, a font that resolves, a shell that loads — not file contents.
#
# --static is the mode to run on a fresh machine: it checks that everything the
# repo requires is actually installed, without starting a terminal, a pty or a
# tmux server.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0
STATIC=0

for arg in "$@"; do
  case "$arg" in
    --static) STATIC=1 ;;
    -h|--help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'verify: unknown option %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [[ -t 1 ]]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
  DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; RED=""; YELLOW=""; DIM=""; BOLD=""; RESET=""
fi

pass() { printf '  %spass%s  %-28s %s%s%s\n' "$GREEN" "$RESET" "$1" "$DIM" "${2:-}" "$RESET"; }
fail() { printf '  %sFAIL%s  %-28s %s\n' "$RED" "$RESET" "$1" "${2:-}"; FAILURES=$((FAILURES + 1)); }
warn() { printf '  %swarn%s  %-28s %s\n' "$YELLOW" "$RESET" "$1" "${2:-}"; }

finish() {
  printf '\n'
  if (( FAILURES == 0 )); then
    printf '%s%d failed%s\n\n' "$GREEN" "$FAILURES" "$RESET"
    exit 0
  else
    printf '%s%d failed%s\n\n' "$RED" "$FAILURES" "$RESET"
    exit 1
  fi
}

printf '\n%sverify%s  %s%s%s\n\n' "$BOLD" "$RESET" "$ROOT" \
  "$([[ $STATIC == 1 ]] && printf '  (static)' || true)" "$DIM"
printf '%s' "$RESET"

# ============================================================ static checks
# Everything here is answerable from the checkout and $HOME, with no app
# running. This is what proves a fresh machine got what the repo promises.

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

# ------------------------------------------------------- Required binaries
# The manifest can be satisfied while a binary is still missing (renamed
# formula, wrong prefix), so check the commands the configs actually call.
REQUIRED_CMDS=(chezmoi age tmux btop eza bat delta lazygit yazi ya opencode zsh git)
MISSING=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done
[[ -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
  || MISSING+=("zsh-autosuggestions")
[[ -r /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  || MISSING+=("zsh-syntax-highlighting")
if [[ ${#MISSING[@]} -eq 0 ]]; then
  pass "required tools" "${#REQUIRED_CMDS[@]} commands + 2 shell plugins"
else
  fail "required tools" "missing: ${MISSING[*]}"
fi

# ------------------------------------------------------- Shell framework
# Oh My Zsh publishes no tags, so bootstrap.sh pins commits. Read the pins from
# there rather than repeating them; drift means the machine was built with an
# older script.
OMZ_PIN="$(sed -n 's/^OMZ_PIN="\(.*\)"$/\1/p' "$ROOT/bootstrap.sh" | head -1)"
P10K_PIN="$(sed -n 's/^P10K_PIN="\(.*\)"$/\1/p' "$ROOT/bootstrap.sh" | head -1)"
OMZ_DIR="$HOME/.oh-my-zsh"
P10K_DIR="$OMZ_DIR/custom/themes/powerlevel10k"
FRAMEWORK_ISSUES=()
[[ -f "$OMZ_DIR/oh-my-zsh.sh" ]] || FRAMEWORK_ISSUES+=("oh-my-zsh missing")
[[ -f "$P10K_DIR/powerlevel10k.zsh-theme" ]] || FRAMEWORK_ISSUES+=("powerlevel10k missing")
if [[ -f "$OMZ_DIR/oh-my-zsh.sh" && -n "$OMZ_PIN" ]]; then
  actual="$(git -C "$OMZ_DIR" rev-parse HEAD 2>/dev/null)"
  [[ "$actual" == "$OMZ_PIN" ]] || FRAMEWORK_ISSUES+=("oh-my-zsh at ${actual:0:7}, pin ${OMZ_PIN:0:7}")
fi
if [[ -f "$P10K_DIR/powerlevel10k.zsh-theme" && -n "$P10K_PIN" ]]; then
  actual="$(git -C "$P10K_DIR" rev-parse HEAD 2>/dev/null)"
  [[ "$actual" == "$P10K_PIN" ]] || FRAMEWORK_ISSUES+=("powerlevel10k at ${actual:0:7}, pin ${P10K_PIN:0:7}")
fi
if [[ ${#FRAMEWORK_ISSUES[@]} -eq 0 ]]; then
  pass "shell framework" "oh-my-zsh + powerlevel10k at pinned commits"
else
  fail "shell framework" "${FRAMEWORK_ISSUES[*]}"
fi

# ------------------------------------------------------- Optional toolchains
# Guarded in the shell configs on purpose: absent is a warning, never a failure.
OPTIONAL_ISSUES=()
[[ -x "$HOME/.cargo/bin/cargo" ]] || OPTIONAL_ISSUES+=("rust/cargo")
[[ -s "$HOME/.nvm/nvm.sh" ]] || OPTIONAL_ISSUES+=("nvm")
command -v docker >/dev/null 2>&1 || OPTIONAL_ISSUES+=("docker")
[[ -d "$HOME/Library/Application Support/Herd" ]] || OPTIONAL_ISSUES+=("herd")
if [[ ${#OPTIONAL_ISSUES[@]} -eq 0 ]]; then
  pass "optional tools" "all present"
else
  warn "optional tools" "absent (guarded, not required): ${OPTIONAL_ISSUES[*]}"
fi

# -------------------------------------------------- OpenCode and agent skills
# Secrets and machine-local state must never enter the source. These fail
# instead of warn: a leak is never acceptable, even on an otherwise healthy
# machine. The guard list lives in .chezmoiignore as well.
if command -v chezmoi >/dev/null 2>&1; then
  LEAKED="$(chezmoi managed --path-style absolute 2>/dev/null \
    | grep -E '/(auth\.json|service\.json|opencode\.db(-wal|-shm)?)$' || true)"
  if [[ -z "$LEAKED" ]]; then
    pass "secrets unmanaged" "no auth/service/db in source"
  else
    fail "secrets unmanaged" "$(printf '%s' "$LEAKED" | head -1)"
  fi

  if [[ -n "$(grep -rlE '"(password|apiKey|api_key|secret|token)"[[:space:]]*:' \
        "$ROOT/dot_config/opencode" 2>/dev/null)" ]]; then
    fail "opencode config" "secret-shaped key in a managed file"
  else
    pass "opencode config" "no secret-shaped keys"
  fi
fi

# ------------------------------------------------------- licensed assets guard
# MonoLisa is commercial and must never be committed. `chezmoi add --recursive`
# is the command that would do it by accident, so check the index, not $HOME.
if command -v git >/dev/null 2>&1 && [[ -d "$ROOT/.git" ]]; then
  TRACKED_FONTS="$(git -C "$ROOT" ls-files | grep -Ei '(^private_Library/)|\.(ttf|otf|ttc)$' || true)"
  if [[ -z "$TRACKED_FONTS" ]]; then
    pass "licensing" "no font binaries tracked"
  else
    fail "licensing" "font binary tracked: $(printf '%s' "$TRACKED_FONTS" | head -1)"
  fi
else
  warn "licensing" "skipped, not a git checkout"
fi

(( STATIC == 1 )) && finish

# =========================================================== runtime checks
# Everything below needs the applied machine: the apps, a pty, a tmux server.

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

# ---------------------------------------------------------------- btop theme
if command -v btop >/dev/null 2>&1; then
  BTOP_CONFIG="$HOME/.config/btop/btop.conf"
  BTOP_THEME="$(awk -F'"' '/^color_theme/ {print $2}' "$BTOP_CONFIG" 2>/dev/null)"
  case "$BTOP_THEME" in
    ""|Default|TTY)
      pass "btop theme" "${BTOP_THEME:-builtin}"
      ;;
    *)
      if [[ -f "$HOME/.config/btop/themes/$BTOP_THEME.theme" ]]; then
        pass "btop theme" "$BTOP_THEME"
      else
        fail "btop theme" "config names '$BTOP_THEME' but that theme file is missing"
      fi
      ;;
  esac
else
  fail "btop" "not installed"
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
  MISSING_PLUGINS=(); WRONGREF=(); SPECS=0
  while IFS= read -r spec; do
    name="${spec%%#*}"; name="${name##*/}"
    ref="${spec##*#}"
    dir="$HOME/.tmux/plugins/$name"
    SPECS=$((SPECS + 1))
    if [[ ! -d "$dir" ]]; then
      MISSING_PLUGINS+=("$name")
      continue
    fi
    actual="$(git -C "$dir" describe --tags --always 2>/dev/null)"
    if [[ "$actual" != "$ref" ]]; then WRONGREF+=("$name@$actual"); fi
  done < <(sed -n "s/^[[:space:]]*set -g @plugin '\(.*\)'.*/\1/p" "$HOME/.tmux.conf")
  if (( SPECS == 0 )); then
    fail "tmux plugins" "no @plugin lines readable from ~/.tmux.conf"
  elif [[ ${#MISSING_PLUGINS[@]} -eq 0 && ${#WRONGREF[@]} -eq 0 ]]; then
    pass "tmux plugins" "$SPECS at pinned refs"
  else
    [[ ${#MISSING_PLUGINS[@]} -gt 0 ]] && fail "tmux plugins" "missing: ${MISSING_PLUGINS[*]}"
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

# ------------------------------------------------------------ OpenCode config
if command -v chezmoi >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1 \
     && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$HOME/.config/opencode/cli.json" 2>/dev/null; then
    pass "opencode config" "cli.json parses"
  else
    fail "opencode config" "~/.config/opencode/cli.json missing or invalid"
  fi

  SKILLS="$(find "$HOME/.agents/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$SKILLS" -gt 0 ]]; then
    pass "agent skills" "$SKILLS global skills"
  else
    warn "agent skills" "none in ~/.agents/skills — run chezmoi apply"
  fi
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

finish
