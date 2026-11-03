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

DOTFILES_ROOT="$ROOT"
# shellcheck source=lib-selection.sh
source "$ROOT/scripts/lib-selection.sh"
# shellcheck source=lib-skills.sh
source "$ROOT/scripts/lib-skills.sh"

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

# ---------------------------------------------------- Optional selection
# The machine is judged against its own saved selection, not the full inventory.
selection_load_items
SELECTION_PRESENT=0
selection_load_file && SELECTION_PRESENT=1 || true

# Before a selection exists (an older machine, or a fresh checkout), treat every
# config as enabled so the check does not fail the upgrade.
config_enabled() {
  if (( SELECTION_PRESENT )); then sel_has "$1"; else return 0; fi
}

if (( SELECTION_PRESENT )); then
  TMP_BREWFILE="$(mktemp "${TMPDIR:-/tmp}/verify-brewfile.XXXXXX")"
  ( DOTFILES_BREWFILE="$TMP_BREWFILE"; selection_render_brewfile )
  if grep -qE '^(brew|cask|vscode|npm) ' "$TMP_BREWFILE"; then
    if command -v brew >/dev/null 2>&1 \
       && HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="$TMP_BREWFILE" >/dev/null 2>&1; then
      pass "optional packages" "selection satisfied"
    else
      fail "optional packages" "run: $ROOT/bootstrap.sh --select"
    fi
  else
    pass "optional packages" "none selected"
  fi
  rm -f "$TMP_BREWFILE"

  CONFIG_ISSUES=(); STALE_CONFIGS=()
  i=0
  while (( i < ITEM_N )); do
    if [[ -n "${ITEM_PATHS[$i]}" ]]; then
      if sel_has "${ITEM_ID[$i]}"; then
        first_path="${ITEM_PATHS[$i]%%,*}"
        [[ -e "$HOME/$first_path" || -L "$HOME/$first_path" ]] \
          || CONFIG_ISSUES+=("${ITEM_ID[$i]}")
      else
        for p in ${ITEM_PATHS[$i]//,/ }; do
          if [[ -e "$HOME/$p" || -L "$HOME/$p" ]]; then
            STALE_CONFIGS+=("${ITEM_ID[$i]}")
            break
          fi
        done
      fi
    fi
    i=$((i + 1))
  done
  if [[ ${#CONFIG_ISSUES[@]} -eq 0 ]]; then
    pass "selected configs" "all applied"
  else
    fail "selected configs" "missing: ${CONFIG_ISSUES[*]}"
  fi
  if [[ ${#STALE_CONFIGS[@]} -eq 0 ]]; then
    pass "deselected configs" "not applied"
  else
    warn "deselected configs" "stale, remove with: $ROOT/bootstrap.sh --prune (${STALE_CONFIGS[*]})"
  fi
else
  warn "optional selection" "none saved — run: $ROOT/bootstrap.sh --select"
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

# ------------------------------------------------------------ OpenCode secrets
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

# ------------------------------------------------------------- agent skills
# Skills are floating upstream checkouts linked into ~/.agents/skills, not
# managed files. Missing or stale links warn so a machine bootstrapped offline
# still counts as healthy; a missing target directory is fatal because no agent
# can see any skill at all.
if ! skills_load_upstreams; then
  fail "skills manifest" "${SKILLS_CONF_ERRORS//$'\n'/; }"
elif [[ ! -d "$SKILLS_TARGET_DIR" ]]; then
  fail "agent skills" "missing $SKILLS_TARGET_DIR — run: $ROOT/bootstrap.sh"
else
  SKILL_LINK_ISSUES=(); CHECKOUT_ISSUES=(); MISSING_UPSTREAM=0; SKILL_TOTAL=0
  EXPECTED=$'\n'
  i=0
  while (( i < UP_N )); do
    repo="${UP_REPO[$i]}"
    checkout="$(skills_checkout_dir "$repo")"
    if [[ ! -d "$checkout/.git" ]]; then
      CHECKOUT_ISSUES+=("$repo missing")
      MISSING_UPSTREAM=1
    elif [[ -n "$(git -C "$checkout" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
      CHECKOUT_ISSUES+=("$repo dirty")
    fi
    while IFS= read -r source; do
      [[ -n "$source" ]] || continue
      SKILL_TOTAL=$((SKILL_TOTAL + 1))
      skill_name="$(basename "$source")"
      EXPECTED="$EXPECTED$skill_name"$'\n'
      skill_link="$SKILLS_TARGET_DIR/$skill_name"
      if [[ ! -L "$skill_link" ]] || [[ "$(readlink "$skill_link")" != "$source" ]]; then
        SKILL_LINK_ISSUES+=("$skill_name")
      fi
    done < <(skills_skill_dirs "$repo" "${UP_INCLUDES[$i]}")
    i=$((i + 1))
  done

  if (( MISSING_UPSTREAM )); then
    warn "agent skills" "not every upstream is checked out — run: $ROOT/bootstrap.sh"
  elif [[ ${#SKILL_LINK_ISSUES[@]} -eq 0 ]]; then
    pass "agent skills" "$SKILL_TOTAL linked from $UP_N upstreams"
  else
    warn "agent skills" "missing or wrong link: ${SKILL_LINK_ISSUES[*]} — run: $ROOT/bootstrap.sh"
  fi

  if [[ ${#CHECKOUT_ISSUES[@]} -eq 0 ]]; then
    pass "skill checkouts" "$UP_N clean"
  else
    warn "skill checkouts" "${CHECKOUT_ISSUES[*]}"
  fi

  DANGLING=(); STALE=()
  for entry in "$SKILLS_TARGET_DIR"/*; do
    [[ -L "$entry" ]] || continue
    dest="$(readlink "$entry")"
    case "$dest" in
      "$SKILLS_UPSTREAM_DIR"/*)
        skill_name="$(basename "$entry")"
        if [[ ! -e "$dest" ]]; then
          DANGLING+=("$skill_name")
        elif (( ! MISSING_UPSTREAM )); then
          case "$EXPECTED" in
            *$'\n'"$skill_name"$'\n'*) ;;
            *) STALE+=("$skill_name") ;;
          esac
        fi
        ;;
    esac
  done
  if [[ ${#DANGLING[@]} -eq 0 && ${#STALE[@]} -eq 0 ]]; then
    pass "skill links" "no stray links"
  else
    [[ ${#DANGLING[@]} -gt 0 ]] && warn "skill links" "dangling: ${DANGLING[*]}"
    [[ ${#STALE[@]} -gt 0 ]] && warn "skill links" "not declared: ${STALE[*]} — run: $ROOT/bootstrap.sh"
  fi
fi

# ------------------------------------------------------- licensed assets guard
# A commercial font must never be committed: it cannot be redistributed, and
# `chezmoi add --recursive` is the command that would do it by accident. Check
# the index, not $HOME. Nothing here needs a font binary any more.
if command -v git >/dev/null 2>&1 && [[ -d "$ROOT/.git" ]]; then
  TRACKED_FONTS="$(git -C "$ROOT" ls-files | grep -Ei '(^private_Library/)|\.(ttf|otf|ttc)$' || true)"
  if [[ -z "$TRACKED_FONTS" ]]; then
    pass "licensing" "no font binaries tracked"
  else
    fail "licensing" "font binary tracked: $(printf '%s' "$TRACKED_FONTS" | head -1)"
  fi

  TRACKED_SKILLS="$(git -C "$ROOT" ls-files dot_agents .opencode/skills 2>/dev/null || true)"
  if [[ -z "$TRACKED_SKILLS" ]]; then
    pass "skills unvendored" "no skill trees tracked"
  else
    fail "skills unvendored" "vendored copy tracked: $(printf '%s' "$TRACKED_SKILLS" | head -1)"
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
  if ! config_enabled config:ghostty; then
    warn "ghostty config" "not selected"
  else
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
  fi

  # ----------------------------------------------------------- Font fallback
  # 0x61 = 'a' (text), 0xf07b = nerd font folder glyph, 0xe5ff = nerd font
  # icon. One font must answer all three: Maple Mono NF ships the icon set, so
  # there is no separate symbols fallback to keep in sync.
  TEXT_FACE="$("$GHOSTTY_BIN" +show-face --cp=0x61 2>/dev/null | head -1)"
  ICON_FACE="$("$GHOSTTY_BIN" +show-face --cp=0xf07b 2>/dev/null | head -1)"
  if [[ "$TEXT_FACE" == *"Maple Mono NF"* ]]; then
    pass "font: text face" "Maple Mono NF"
  else
    fail "font: text face" "expected Maple Mono NF — run: brew bundle install --file=$ROOT/Brewfile"
  fi
  if [[ "$ICON_FACE" == *"Maple Mono NF"* ]]; then
    pass "font: icons" "drawn by the text face"
  else
    fail "font: icons" "icons would render as boxes — see docs/fonts.md"
  fi
else
  warn "font checks" "skipped, Ghostty not found"
fi

# ---------------------------------------------------------------- btop theme
if command -v btop >/dev/null 2>&1; then
  if ! config_enabled config:btop; then
    warn "btop theme" "not selected"
  else
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
  fi
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
if ! config_enabled config:tmux; then
  warn "tmux config" "not selected"
elif command -v tmux >/dev/null 2>&1; then
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
  if ! config_enabled config:opencode; then
    warn "opencode config" "not selected"
  elif command -v python3 >/dev/null 2>&1 \
     && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$HOME/.config/opencode/cli.json" 2>/dev/null; then
    pass "opencode config" "cli.json parses"
  else
    fail "opencode config" "~/.config/opencode/cli.json missing or invalid"
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
