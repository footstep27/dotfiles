#!/usr/bin/env bash
# Does the optional inventory parser, selection model and generators behave?
#
#   ./scripts/check-selection.sh
#
# Runs against a throwaway $HOME. No brew, no chezmoi, no network.

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

printf '\n%soptional selection%s\n\n' "$BOLD" "$RESET"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-selection.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

export HOME="$TMP"
export DOTFILES_ROOT="$ROOT"
# shellcheck source=lib-selection.sh
source "$ROOT/scripts/lib-selection.sh"

selection_load_items
if (( ITEM_N > 100 )) && (( CAT_N == 10 )); then
  pass "manifest loads" "$ITEM_N items in $CAT_N categories"
else
  fail "manifest loads" "got $ITEM_N items in $CAT_N categories"
fi

MISSING_DESC=0
i=0
while (( i < ITEM_N )); do
  [[ -z "${ITEM_DESC[$i]}" ]] && MISSING_DESC=$((MISSING_DESC + 1))
  i=$((i + 1))
done
if (( MISSING_DESC == 0 )); then
  pass "descriptions" "every item has a summary"
else
  fail "descriptions" "$MISSING_DESC item(s) missing a summary"
fi

selection_defaults
if [[ "$(selection_selected_count)" == "5" ]] && sel_has config:opencode; then
  pass "first-run defaults" "5 config toggles, no packages"
else
  fail "first-run defaults" "got $(selection_selected_count)"
fi

if item_index macos:keyboard >/dev/null 2>&1 && ! sel_has macos:keyboard; then
  pass "macos toggles" "present and default off"
else
  fail "macos toggles" "missing or selected by default"
fi

sel_del config:ghostty
if ! sel_has config:ghostty && sel_has config:tmux; then
  pass "toggle one config" "neighbours untouched"
else
  fail "toggle one config" "selection lost a neighbour"
fi

selection_enable brew:ffmpeg >/dev/null
if selection_enable brew:ffmpeg-full; then
  fail "conflict blocks" "ffmpeg-full was selected"
else
  pass "conflict blocks" "conflicts with $SELECTION_LAST_CONFLICT"
fi

selection_enable vscode:ms-python.python >/dev/null
if sel_has cask:visual-studio-code; then
  pass "requires cascades in" "VS Code added for its extension"
else
  fail "requires cascades in" "parent not selected"
fi

sel_del cask:visual-studio-code
selection_prune_dependents
if ! sel_has vscode:ms-python.python; then
  pass "requires cascades out" "extension removed with its parent"
else
  fail "requires cascades out" "orphan extension remains"
fi

selection_render_ignore
if grep -qx '.wezterm.lua' "$DOTFILES_IGNORE_FILE"; then
  pass "ignore generation" "unchecked WezTerm config excluded"
else
  fail "ignore generation" "missing .wezterm.lua"
fi

mkdir -p "$HOME/.config/ghostty"
printf 'stale\n' > "$HOME/.config/ghostty/config"
REMOVED="$(selection_prune_paths)"
if [[ "$REMOVED" == "1" ]] && [[ ! -e "$HOME/.config/ghostty/config" ]]; then
  pass "prune" "deselected config removed"
else
  fail "prune" "expected 1 removal, got $REMOVED"
fi

if selection_validate >/dev/null; then
  pass "validation" "dependencies and conflicts resolved"
else
  fail "validation" "selection is inconsistent"
fi

selection_write_inventory
if ! selection_inventory_changed; then
  pass "inventory snapshot" "matches the manifests"
else
  fail "inventory snapshot" "reports a change immediately after writing"
fi

SNAPSHOT="$DOTFILES_INVENTORY_FILE.tmp"
grep -vx 'brew:ghidra' "$DOTFILES_INVENTORY_FILE" > "$SNAPSHOT"
mv "$SNAPSHOT" "$DOTFILES_INVENTORY_FILE"
if selection_inventory_changed && [[ "$(selection_new_item_count)" == "1" ]]; then
  pass "new inventory item" "one addition detected"
else
  fail "new inventory item" "addition not detected"
fi

OLD=$'\nconfig:ghostty\nconfig:tmux\n'
NEW=$'\nconfig:ghostty\nbrew:ghidra\n'
ADDED="$(selection_diff_added "$OLD" "$NEW")"
REMOVED="$(selection_diff_removed "$OLD" "$NEW")"
if [[ "$ADDED" == "brew:ghidra" && "$REMOVED" == "config:tmux" ]]; then
  pass "selection diff" "one addition and one removal"
else
  fail "selection diff" "got added='$ADDED' removed='$REMOVED'"
fi

printf '%s\n' brew:ghidra > "$TMP/delta-ids"
selection_render_brewfile_ids "$(cat "$TMP/delta-ids")" "$TMP/delta.brewfile"
if grep -qx 'brew "ghidra"' "$TMP/delta.brewfile" && ! grep -q 'jadx' "$TMP/delta.brewfile"; then
  pass "delta brewfile" "only the added package"
else
  fail "delta brewfile" "unexpected contents"
fi

SELECTED=$'\n'
mkdir -p "$HOME/.config/opencode" "$HOME/.config/yazi"
printf 'x\n' > "$HOME/.config/opencode/cli.json"
printf 'x\n' > "$HOME/.config/yazi/yazi.toml"
REMOVED="$(selection_prune_paths $'\nconfig:opencode\n')"
if [[ "$REMOVED" == "1" ]] && [[ ! -e "$HOME/.config/opencode/cli.json" ]] \
   && [[ -e "$HOME/.config/yazi/yazi.toml" ]]; then
  pass "delta prune" "only the removed config"
else
  fail "delta prune" "removed $REMOVED path(s)"
fi

printf '\n'
if (( FAILURES == 0 )); then
  printf '%s%d failed%s\n\n' "$GREEN" "$FAILURES" "$RESET"; exit 0
else
  printf '%s%d failed%s\n\n' "$RED" "$FAILURES" "$RESET"; exit 1
fi
