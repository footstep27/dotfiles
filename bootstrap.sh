#!/usr/bin/env bash
# Take a bare Mac to the applied dotfiles setup.
#
#   ./bootstrap.sh            # do it
#   ./bootstrap.sh --dry-run  # show the plan, change nothing
#
# Idempotent: safe to re-run after a partial failure or to pick up updates.
# Order matters — brew → required packages → chezmoi/age → apply → tmux plugins
# → yazi packages → verify — because chezmoi must write the configs before
# anything reads them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; fi

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

# ---------------------------------------------------------------- 1. Homebrew
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

# ------------------------------------------------------- 2. Required packages
step "Required packages"
if (( DRY_RUN )); then
  info "would run: brew bundle install --file=$ROOT/Brewfile"
else
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle install --file="$ROOT/Brewfile" \
    || fail "brew bundle install failed"
fi

command -v chezmoi >/dev/null 2>&1 || (( DRY_RUN )) || fail "chezmoi missing after bundle"

# -------------------------------------------------------- 3. chezmoi source
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

# ------------------------------------------------------------- 4. Backup drift
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

# ---------------------------------------------------------------- 5. Apply
step "Apply"
if (( DRY_RUN )); then
  chezmoi apply --dry-run --verbose 2>&1 | sed 's/^/    /' || true
else
  chezmoi apply --verbose 2>&1 | sed 's/^/    /'
fi

# -------------------------------------------------- 6. Ghostty terminfo
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

# -------------------------------------------------------- 7. tmux plugins
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

if (( DRY_RUN )); then
  info "would install tmux plugins and check out pinned refs"
else
  install_tmux_plugins
  info "plugins: $(ls "$HOME/.tmux/plugins" | tr '\n' ' ')"
fi

# -------------------------------------------------------- 8. yazi packages
# Flavors and plugins are not vendored; package.toml pins them and `ya`
# installs the exact refs recorded there.
step "yazi packages"
if (( DRY_RUN )); then
  info "would install yazi packages pinned in ~/.config/yazi/package.toml"
elif command -v ya >/dev/null 2>&1; then
  ya pkg install
  info "packages: $(ya pkg list 2>/dev/null | tail -n +2 | tr '\n' ' ')"
else
  warn "ya not found — skipping yazi packages"
fi

# ---------------------------------------------------------------- 9. Verify
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

printf '\n%sDone.%s Next: open Ghostty. Two steps stay manual — see README.\n' \
  "$GREEN" "$RESET"
