#!/usr/bin/env bash
# Take a bare Mac to the applied dotfiles setup.
#
#   ./bootstrap.sh                     # do it, reusing the saved selection
#   ./bootstrap.sh --select            # edit the optional inventory
#   ./bootstrap.sh --all-optional      # select every non-conflicting optional item
#   ./bootstrap.sh --reset-selection   # forget the saved selection
#   ./bootstrap.sh --prune             # delete configs the selection excludes
#   ./bootstrap.sh --dry-run           # show the plan, change nothing
#
# Idempotent: safe to re-run after a partial failure or to pick up updates.
# Order matters — Command Line Tools → brew → optional inventory → required
# packages → optional packages → chezmoi/age → apply → shell framework → tmux
# plugins → yazi packages → verify — because chezmoi must write the configs
# before anything reads them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
DO_SELECT=0
ALL_OPTIONAL=0
RESET_SELECTION=0
PRUNE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)         DRY_RUN=1 ;;
    --select)          DO_SELECT=1 ;;
    --all-optional)    ALL_OPTIONAL=1 ;;
    --reset-selection) RESET_SELECTION=1 ;;
    --prune)           PRUNE=1 ;;
    -h|--help)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'bootstrap: unknown option %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

if (( DO_SELECT && ALL_OPTIONAL )); then
  printf 'bootstrap: --select and --all-optional are mutually exclusive\n' >&2
  exit 2
fi

DOTFILES_ROOT="$ROOT"
# shellcheck source=scripts/lib-selection.sh
source "$ROOT/scripts/lib-selection.sh"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

step() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$1"; }
info() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '%s    warn:%s %s\n' "$YELLOW" "$RESET" "$1"; }
fail() { printf '%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

if (( DRY_RUN )); then
  printf '%sDRY RUN%s — nothing will be modified\n\n' "$YELLOW" "$RESET"
fi

# ------------------------------------------------- 1. Command Line Tools
# A genuinely bare Mac has no git and no compiler, which means it cannot clone
# this repo and Homebrew's installer refuses to run. There is no unattended
# install: `xcode-select --install` opens a GUI dialog, so this step only
# reports the truth instead of failing three steps later.
step "Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  info "present: $(xcode-select -p)"
else
  fail "Command Line Tools missing — run 'xcode-select --install', finish the dialog, then re-run this script"
fi

# ---------------------------------------------------------------- 2. Homebrew
step "Homebrew"
if command -v brew >/dev/null 2>&1; then
  info "present: $(command -v brew)"
else
  info "not found — installing"
  if (( DRY_RUN )); then
    info "would run: official Homebrew installer"
  else
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || fail "Homebrew installation failed"
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  fi
fi

# --------------------------------------------------- 3. Optional inventory
# The selection is machine-local state, not repository content. First run on a
# terminal opens the checklist; later runs reuse the saved file. --dry-run
# browses read-only and never writes it.
step "Optional inventory"
selection_load_items
SELECTION_SAVED=0
selection_load_file && SELECTION_SAVED=1 || true
selection_prune_dependents

if (( RESET_SELECTION )); then
  if (( DRY_RUN )); then
    SELECTED=$'\n'
    SELECTION_SAVED=0
    info "would clear the saved selection"
  else
    selection_reset
    SELECTION_SAVED=0
    info "saved selection cleared"
  fi
fi

if (( ALL_OPTIONAL )); then
  selection_select_all
  SELECTION_SAVED=1
  info "selected every non-conflicting optional item"
fi

if (( DRY_RUN )); then
  if (( DO_SELECT )) || { (( ! SELECTION_SAVED )) && [[ -t 0 && -t 1 ]]; }; then
    "$ROOT/scripts/select.sh" --readonly || true
    selection_load_file && SELECTION_SAVED=1 || true
    (( SELECTION_SAVED )) || selection_defaults
  elif (( ! SELECTION_SAVED )); then
    selection_defaults
  fi
  info "would use $(selection_selected_count)/$(selection_optional_count) optional items"
  if [[ -f "$DOTFILES_SELECTION_FILE" ]]; then
    info "selection file: $DOTFILES_SELECTION_FILE"
  else
    info "no saved selection — first run would open the checklist"
  fi
  PKG_COUNT=0
  i=0
  while (( i < ITEM_N )); do
    if [[ "${ITEM_LOCKED[$i]}" != 1 ]] && sel_has "${ITEM_ID[$i]}" \
       && [[ "${ITEM_KIND[$i]}" != "config" ]]; then
      info "would install: ${ITEM_KIND[$i]} ${ITEM_NAME[$i]}"
      PKG_COUNT=$((PKG_COUNT + 1))
    fi
    i=$((i + 1))
  done
  (( PKG_COUNT )) || info "no optional packages selected"
else
  if (( DO_SELECT )); then
    "$ROOT/scripts/select.sh" || fail "selection cancelled — nothing installed"
    selection_load_file || true
    SELECTION_SAVED=1
  elif (( ! SELECTION_SAVED )); then
    if [[ -t 0 && -t 1 ]]; then
      "$ROOT/scripts/select.sh" || fail "selection cancelled — nothing installed"
      selection_load_file || true
      SELECTION_SAVED=1
    else
      selection_defaults
      warn "no terminal and no saved selection — applying required configs only"
      SELECTION_SAVED=1
    fi
  fi
  selection_generate
  selection_save
  info "selected $(selection_selected_count)/$(selection_optional_count) optional items"
fi

# ------------------------------------------------------- 4. Required packages
step "Required packages"
if (( DRY_RUN )); then
  info "would run: brew bundle install --file=$ROOT/Brewfile"
else
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle install --file="$ROOT/Brewfile" \
    || fail "brew bundle install failed"
fi

# ------------------------------------------------------- 5. Optional packages
step "Optional packages"
if (( DRY_RUN )); then
  info "would install the selected optional packages listed above"
elif grep -qE '^(brew|cask|vscode|npm) ' "$DOTFILES_BREWFILE" 2>/dev/null; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle install --file="$DOTFILES_BREWFILE" \
    || fail "optional brew bundle install failed"
else
  info "none selected"
fi

command -v chezmoi >/dev/null 2>&1 || (( DRY_RUN )) || fail "chezmoi missing after bundle"

# -------------------------------------------------------- 6. chezmoi source
step "chezmoi source"
CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
CHEZMOI_AGE_KEY="$HOME/.config/chezmoi/key.txt"

if [[ -f "$CHEZMOI_CONFIG" ]] && grep -q '^sourceDir' "$CHEZMOI_CONFIG" \
   && ! grep -q "^sourceDir *= *\"$ROOT\"" "$CHEZMOI_CONFIG"; then
  warn "$CHEZMOI_CONFIG points somewhere else:"
  warn "  $(grep '^sourceDir' "$CHEZMOI_CONFIG" || echo '(no sourceDir)')"
  warn "expected: sourceDir = \"$ROOT\""
  warn "fix it by hand, or remove the file and re-run"
  (( DRY_RUN )) || exit 1
fi

# Never truncate this file: it may hold encryption settings we did not write.
ensure_chezmoi_config() {
  mkdir -p "$(dirname "$CHEZMOI_CONFIG")"
  touch "$CHEZMOI_CONFIG"
  if ! grep -q '^sourceDir' "$CHEZMOI_CONFIG"; then
    printf 'sourceDir = "%s"\n' "$ROOT" >> "$CHEZMOI_CONFIG"
    info "set sourceDir = $ROOT"
  else
    info "sourceDir already points at this checkout"
  fi

  # age recipient: configured so the first encrypted file is one command away.
  # Nothing in this repo is encrypted today.
  if ! grep -q '^\[age\]' "$CHEZMOI_CONFIG"; then
    if [[ ! -f "$CHEZMOI_AGE_KEY" ]]; then
      age-keygen -o "$CHEZMOI_AGE_KEY" >/dev/null 2>&1 || {
        warn "age-keygen failed — encryption stays unconfigured"
        return 0
      }
      chmod 600 "$CHEZMOI_AGE_KEY"
      info "generated age identity at $CHEZMOI_AGE_KEY"
    fi
    RECIPIENT="$(age-keygen -y "$CHEZMOI_AGE_KEY" 2>/dev/null || true)"
    if [[ -n "$RECIPIENT" ]]; then
      printf '\nencryption = "age"\n[age]\n    identity = "%s"\n    recipient = "%s"\n' \
        "$CHEZMOI_AGE_KEY" "$RECIPIENT" >> "$CHEZMOI_CONFIG"
      info "configured age recipient ${RECIPIENT:0:16}…"
      info "back up the private key — a new machine cannot decrypt without it"
    fi
  else
    info "age recipient already configured"
  fi
}

if (( DRY_RUN )); then
  info "would ensure $CHEZMOI_CONFIG (sourceDir, age recipient)"
else
  ensure_chezmoi_config
fi

# ------------------------------------------------------------- 7. Backup drift
step "Backup"
if (( DRY_RUN )); then
  info "would back up existing dotfiles that differ from the repo"
else
  if command -v chezmoi >/dev/null 2>&1 && [[ -n "$(chezmoi diff 2>/dev/null || true)" ]]; then
    BK="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BK"
    # Every managed file that exists gets archived, not only the differing ones:
    # a restore is easier than reconstructing which files were involved.
    chezmoi managed --path-style absolute | while IFS= read -r f; do
      if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
    done | tar -czf "$BK/dotfiles.tar.gz" -T - 2>/dev/null || true
    printf '%s' "$ROOT" > "$BK/source-dir"
    if [[ -s "$BK/dotfiles.tar.gz" ]]; then
      info "backed up to $BK"
      info "restore with: tar -xzf $BK/dotfiles.tar.gz -C /"
    else
      rmdir "$BK" 2>/dev/null || true
      info "nothing to back up"
    fi
  else
    info "working tree already matches the repo — no backup needed"
  fi
fi

# ---------------------------------------------------------------- 8. Apply
step "Apply"
if (( DRY_RUN )); then
  chezmoi apply --dry-run --verbose 2>&1 | sed 's/^/    /' || true
else
  chezmoi apply --verbose 2>&1 | sed 's/^/    /'
fi

# ---------------------------------------------------------------- 9. Prune
if (( PRUNE )); then
  step "Prune deselected configs"
  if (( DRY_RUN )); then
    info "would delete managed files for unchecked config toggles"
  else
    REMOVED="$(selection_prune_paths)"
    info "removed $REMOVED path(s)"
  fi
fi

# --------------------------------------------------- 10. Shell framework
# Oh My Zsh publishes no tags, so both pins are commit SHAs: the pair this
# machine runs today. Moving either is a deliberate edit, not a side effect of
# the day the machine was built.
OMZ_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
OMZ_PIN="2100c630ba4bd67bb48802c3e7da893a4fdaa1a0"
P10K_REPO="https://github.com/romkatv/powerlevel10k.git"
P10K_PIN="9253fb1c5034410c43a0c681ff8294181c54016c"

ensure_pinned_repo() { # repo dir pin name
  local repo="$1" dir="$2" pin="$3" name="$4"
  if [[ ! -d "$dir/.git" ]]; then
    mkdir -p "$dir"
    git -C "$dir" init --quiet || { warn "$name: init failed"; return 1; }
    git -C "$dir" remote add origin "$repo" 2>/dev/null \
      || git -C "$dir" remote set-url origin "$repo"
    if ! git -C "$dir" fetch --quiet --depth 1 origin "$pin"; then
      warn "$name: could not fetch ${pin:0:7}"
      return 1
    fi
    git -C "$dir" checkout --quiet FETCH_HEAD \
      || { warn "$name: checkout failed"; return 1; }
    info "$name: installed at ${pin:0:7}"
    return 0
  fi
  # Generated files are normal (Oh My Zsh writes completions/), so only tracked
  # modifications count as "do not touch this".
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    warn "$name: local changes — leaving it alone"
    return 0
  fi
  if [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$pin" ]]; then
    info "$name: already at ${pin:0:7}"
    return 0
  fi
  if git -C "$dir" fetch --quiet --depth 1 origin "$pin" \
     && git -C "$dir" checkout --quiet FETCH_HEAD; then
    info "$name: moved to ${pin:0:7}"
  else
    warn "$name: could not move to ${pin:0:7}"
  fi
}

step "Shell framework"
if (( DRY_RUN )); then
  if [[ -d "$HOME/.oh-my-zsh/.git" ]]; then
    info "would check Oh My Zsh is at ${OMZ_PIN:0:7}"
  else
    info "would install Oh My Zsh ${OMZ_PIN:0:7} into ~/.oh-my-zsh"
  fi
  if [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k/.git" ]]; then
    info "would check powerlevel10k is at ${P10K_PIN:0:7}"
  else
    info "would install powerlevel10k ${P10K_PIN:0:7} into ~/.oh-my-zsh/custom/themes"
  fi
else
  ensure_pinned_repo "$OMZ_REPO" "$HOME/.oh-my-zsh" "$OMZ_PIN" "oh-my-zsh" || true
  ensure_pinned_repo "$P10K_REPO" "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" \
    "$P10K_PIN" "powerlevel10k" || true
fi

# ------------------------------------------------- 11. Ghostty terminfo
# Ghostty keeps its terminfo inside the app bundle, where ncurses will not look.
# tmux (and anything over ssh) needs TERM=xterm-ghostty to be resolvable, so the
# bundled entries are copied into the standard per-user location.
step "Ghostty terminfo"
terminfo_src() {
  for app in /Applications/Ghostty.app "$HOME/Applications/Ghostty.app"; do
    if [[ -d "$app/Contents/Resources/terminfo" ]]; then
      printf '%s' "$app/Contents/Resources/terminfo"
      return 0
    fi
  done
  return 1
}
if SRC="$(terminfo_src)"; then
  if (( DRY_RUN )); then
    info "would copy bundled terminfo into ~/.terminfo"
  else
    for entry in "$SRC"/*/; do
      dir="$(basename "$entry")"
      mkdir -p "$HOME/.terminfo/$dir"
      cp -f "$entry"* "$HOME/.terminfo/$dir/" 2>/dev/null || true
    done
    if infocmp -x xterm-ghostty >/dev/null 2>&1; then
      info "xterm-ghostty resolvable"
    else
      warn "terminfo copy did not take effect"
    fi
  fi
else
  warn "Ghostty bundle not found — skipping terminfo"
fi

# ------------------------------------------------------- 12. tmux plugins
# TPM installs missing plugins but never checks out the ref declared after '#',
# so the pins are applied explicitly here.
step "tmux plugins"
install_tmux_plugins() {
  mkdir -p "$HOME/.tmux/plugins"
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
  tmux start-server \; new-session -d
  tmux run-shell "$HOME/.tmux/plugins/tpm/bin/install_plugins" || true
  tmux kill-server 2>/dev/null || true

  # `set -g @plugin 'owner/repo#ref'` → checkout ref in ~/.tmux/plugins/repo
  while IFS= read -r spec; do
    if [[ -z "$spec" || "$spec" != *"#"* ]]; then continue; fi
    name="${spec%%#*}"; name="${name##*/}"
    ref="${spec##*#}"
    dir="$HOME/.tmux/plugins/$name"
    [[ -d "$dir/.git" ]] || continue
    git -C "$dir" fetch --tags --quiet 2>/dev/null || true
    git -C "$dir" checkout --quiet "$ref" 2>/dev/null \
      || warn "$name: could not check out $ref"
  done < <(sed -n "s/^[[:space:]]*set -g @plugin '\(.*\)'.*/\1/p" "$HOME/.tmux.conf")
}

if ! sel_has config:tmux; then
  info "skipped: tmux config not selected"
elif (( DRY_RUN )); then
  info "would install tmux plugins and check out pinned refs"
else
  install_tmux_plugins
  info "plugins: $(ls "$HOME/.tmux/plugins" | tr '\n' ' ')"
fi

# ------------------------------------------------------- 13. yazi packages
# Flavors and plugins are not vendored; package.toml pins them and `ya`
# installs the exact refs recorded there.
step "yazi packages"
if ! sel_has config:yazi; then
  info "skipped: yazi config not selected"
elif (( DRY_RUN )); then
  info "would install yazi packages pinned in ~/.config/yazi/package.toml"
elif command -v ya >/dev/null 2>&1; then
  ya pkg install
  info "packages: $(ya pkg list 2>/dev/null | tail -n +2 | tr '\n' ' ')"
else
  warn "ya not found — skipping yazi packages"
fi

# --------------------------------------------------------------- 14. Verify
step "Verify"
if [[ -x "$ROOT/scripts/verify.sh" ]]; then
  if (( DRY_RUN )); then
    info "would run: $ROOT/scripts/verify.sh"
  else
    "$ROOT/scripts/verify.sh"
  fi
else
  warn "scripts/verify.sh not present — skipping verification"
fi

printf '\n%sDone.%s Next: open Ghostty. Some steps stay manual — see README.\n' \
  "$GREEN" "$RESET"
