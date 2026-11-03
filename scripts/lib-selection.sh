# shellcheck shell=bash
# Shared selection model for the optional inventory.
#
# A category is a line-oriented file in Brewfile.d/:
#
#   # name: Dev CLI
#   brew<TAB>go<TAB><TAB>Go programming language toolchain.
#   cask<TAB>wezterm<TAB>paths=.wezterm.lua,.wezterm-themes/<TAB>GPU-accelerated terminal emulator.
#   vscode<TAB>ms-python.python<TAB>requires=cask:visual-studio-code<TAB>Python language support.
#   config<TAB>opencode<TAB>paths=.config/opencode/opencode.jsonc<TAB>OpenCode agent settings.
#
# The third column holds optional space-separated key=value attributes. Paths
# are target paths, comma-separated, and are used both for the generated
# .chezmoiignore file and for --prune. The fourth column is a one-sentence
# description shown in the checklist. Required packages are read from
# ../Brewfile and marked locked; their descriptions live in required_desc().

DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-$HOME/.local/state/dotfiles}"
DOTFILES_SELECTION_FILE="$DOTFILES_STATE_DIR/selection"
DOTFILES_INVENTORY_FILE="$DOTFILES_STATE_DIR/inventory"
DOTFILES_IGNORE_FILE="$DOTFILES_STATE_DIR/ignored-paths"
DOTFILES_BREWFILE="$DOTFILES_STATE_DIR/Brewfile.selected"

# Parallel arrays: Bash 3.2 on macOS has no associative arrays.
ITEM_N=0
ITEM_CAT=(); ITEM_KIND=(); ITEM_ID=(); ITEM_NAME=()
ITEM_PATHS=(); ITEM_REQUIRES=(); ITEM_CONFLICTS=(); ITEM_LOCKED=(); ITEM_DESC=()
CAT_N=0
CAT_KEY=(); CAT_NAME=()

cat_add() { # key display-name
  local i=0
  while (( i < CAT_N )); do
    [[ "${CAT_KEY[$i]}" == "$1" ]] && return 0
    i=$((i + 1))
  done
  CAT_KEY[CAT_N]="$1"
  CAT_NAME[CAT_N]="$2"
  CAT_N=$((CAT_N + 1))
}

cat_name() {
  local i=0
  while (( i < CAT_N )); do
    if [[ "${CAT_KEY[$i]}" == "$1" ]]; then printf '%s' "${CAT_NAME[$i]}"; return 0; fi
    i=$((i + 1))
  done
  printf '%s' "$1"
}

item_add() { # category kind id name paths requires conflicts locked description
  ITEM_CAT[ITEM_N]="$1"
  ITEM_KIND[ITEM_N]="$2"
  ITEM_ID[ITEM_N]="$3"
  ITEM_NAME[ITEM_N]="$4"
  ITEM_PATHS[ITEM_N]="$5"
  ITEM_REQUIRES[ITEM_N]="$6"
  ITEM_CONFLICTS[ITEM_N]="$7"
  ITEM_LOCKED[ITEM_N]="$8"
  ITEM_DESC[ITEM_N]="$9"
  ITEM_N=$((ITEM_N + 1))
}

item_index() { # id -> index
  local i=0
  while (( i < ITEM_N )); do
    if [[ "${ITEM_ID[$i]}" == "$1" ]]; then printf '%s' "$i"; return 0; fi
    i=$((i + 1))
  done
  return 1
}

item_locked() { # id -> required baseline?
  local i
  i="$(item_index "$1")" || return 1
  [[ "${ITEM_LOCKED[$i]}" == 1 ]]
}

required_category() {
  case "$1" in
    opencode) printf 'dev-cli' ;;
    *)        printf 'terminal' ;;
  esac
}

# Required rows are injected from Brewfile, which cannot carry descriptions, so
# their one-line summaries live here. Everything selectable describes itself in
# the fourth column of its Brewfile.d/ entry.
required_desc() {
  case "$1" in
    chezmoi)                 printf 'Dotfile manager that applies this repository to your home directory.' ;;
    age)                     printf 'Modern file encryption used for chezmoi secrets.' ;;
    tmux)                    printf 'Terminal multiplexer for persistent and split sessions.' ;;
    btop)                    printf 'Resource monitor for CPU, memory, disks and network.' ;;
    eza)                     printf 'Modern ls replacement with icons, git status and tree view.' ;;
    bat)                     printf 'cat with syntax highlighting, line numbers and git markers.' ;;
    git-delta)               printf 'Readable git diffs with syntax highlighting.' ;;
    lazygit)                 printf 'Terminal UI for common git operations.' ;;
    yazi)                    printf 'Fast terminal file manager with previews and Vim keys.' ;;
    zsh-autosuggestions)     printf 'Fish-style history suggestions in the zsh prompt.' ;;
    zsh-syntax-highlighting) printf 'Live syntax highlighting while typing in zsh.' ;;
    ghostty)                 printf 'GPU-accelerated terminal emulator configured by this repo.' ;;
    font-maple-mono-nf)      printf 'Maple Mono Nerd Font with text, code and icon glyphs.' ;;
    opencode)                printf 'AI coding agent CLI whose configuration is managed here.' ;;
  esac
}

selection_load_items() {
  ITEM_N=0; ITEM_CAT=(); ITEM_KIND=(); ITEM_ID=(); ITEM_NAME=()
  ITEM_PATHS=(); ITEM_REQUIRES=(); ITEM_CONFLICTS=(); ITEM_LOCKED=(); ITEM_DESC=()
  CAT_N=0; CAT_KEY=(); CAT_NAME=()

  local f key name line rest kind id attrs desc a paths requires conflicts
  # First pass: category names and order, so required rows can be inserted into
  # an existing category before the optional rows.
  for f in "$DOTFILES_ROOT"/Brewfile.d/*.txt; do
    [[ -e "$f" ]] || continue
    key="$(basename "$f" .txt)"
    key="${key#[0-9][0-9]-}"
    name="$(sed -n 's/^# name:[[:space:]]*//p' "$f" | head -n 1)"
    [[ -n "$name" ]] || name="$key"
    cat_add "$key" "$name"
  done

  # Required baseline: always installed, never in the selection.
  while IFS= read -r line; do
    case "$line" in
      brew\ \"*\"|cask\ \"*\") ;;
      *) continue ;;
    esac
    kind="${line%% *}"
    id="${line#*\"}"
    id="${id%\"}"
    [[ -n "$id" ]] || continue
    key="$(required_category "$id")"
    cat_add "$key" "$(cat_name "$key")"
    item_add "$key" "$kind" "$kind:$id" "$id" "" "" "" 1 "$(required_desc "$id")"
  done < "$DOTFILES_ROOT/Brewfile"

  # Optional rows, after the required ones so config toggles sit beneath their
  # locked tool.
  for f in "$DOTFILES_ROOT"/Brewfile.d/*.txt; do
    [[ -e "$f" ]] || continue
    key="$(basename "$f" .txt)"
    key="${key#[0-9][0-9]-}"
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      # Split on literal tabs by hand: `read` treats a tab as IFS whitespace,
      # which collapses consecutive tabs and loses an empty attributes column.
      kind="${line%%$'\t'*}"
      rest="${line#*$'\t'}"
      id="${rest%%$'\t'*}"
      attrs=""; desc=""
      case "$rest" in
        *$'\t'*)
          rest="${rest#*$'\t'}"
          attrs="${rest%%$'\t'*}"
          case "$rest" in
            *$'\t'*) desc="${rest#*$'\t'}" ;;
          esac
          ;;
      esac
      [[ -n "$kind" && -n "$id" ]] || continue
      paths=""; requires=""; conflicts=""
      for a in $attrs; do
        case "$a" in
          paths=*)     paths="${a#paths=}" ;;
          requires=*)  requires="${a#requires=}" ;;
          conflicts=*) conflicts="${a#conflicts=}" ;;
        esac
      done
      item_add "$key" "$kind" "$kind:$id" "$id" "$paths" "$requires" "$conflicts" 0 "$desc"
    done < "$f"
  done

  selection_sort_items
}

# Group by category order, required rows before optional rows, preserving the
# order within each group. The menu renders one header per category, so this
# ordering is what makes the list readable.
selection_sort_items() {
  local c i n=0
  local -a NC=() NK=() NI=() NN=() NP=() NR=() NX=() NL=() ND=()
  c=0
  while (( c < CAT_N )); do
    for pass in 1 0; do
      i=0
      while (( i < ITEM_N )); do
        if [[ "${ITEM_CAT[$i]}" == "${CAT_KEY[$c]}" && "${ITEM_LOCKED[$i]}" == "$pass" ]]; then
          NC[n]="${ITEM_CAT[$i]}"; NK[n]="${ITEM_KIND[$i]}"; NI[n]="${ITEM_ID[$i]}"
          NN[n]="${ITEM_NAME[$i]}"; NP[n]="${ITEM_PATHS[$i]}"
          NR[n]="${ITEM_REQUIRES[$i]}"; NX[n]="${ITEM_CONFLICTS[$i]}"
          NL[n]="${ITEM_LOCKED[$i]}"; ND[n]="${ITEM_DESC[$i]}"
          n=$((n + 1))
        fi
        i=$((i + 1))
      done
    done
    c=$((c + 1))
  done
  ITEM_N=$n
  ITEM_CAT=(); ITEM_KIND=(); ITEM_ID=(); ITEM_NAME=()
  ITEM_PATHS=(); ITEM_REQUIRES=(); ITEM_CONFLICTS=(); ITEM_LOCKED=(); ITEM_DESC=()
  i=0
  while (( i < n )); do
    ITEM_CAT[i]="${NC[$i]}"; ITEM_KIND[i]="${NK[$i]}"; ITEM_ID[i]="${NI[$i]}"
    ITEM_NAME[i]="${NN[$i]}"; ITEM_PATHS[i]="${NP[$i]}"
    ITEM_REQUIRES[i]="${NR[$i]}"; ITEM_CONFLICTS[i]="${NX[$i]}"
    ITEM_LOCKED[i]="${NL[$i]}"; ITEM_DESC[i]="${ND[$i]}"
    i=$((i + 1))
  done
}

# The selection is a newline-delimited set with a leading sentinel newline.
sel_has() {
  case "$SELECTED" in
    *$'\n'"$1"$'\n'*) return 0 ;;
  esac
  return 1
}

sel_add() {
  sel_has "$1" || SELECTED="$SELECTED$1"$'\n'
}

sel_del() {
  local out=$'\n' line
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == "$1" ]] && continue
    out="$out$line"$'\n'
  done <<< "$SELECTED"
  SELECTED="$out"
}

selection_defaults() {
  SELECTED=$'\n'
  local i=0
  while (( i < ITEM_N )); do
    [[ "${ITEM_KIND[$i]}" == "config" ]] && sel_add "${ITEM_ID[$i]}"
    i=$((i + 1))
  done
}

selection_load_file() {
  SELECTED=$'\n'
  [[ -f "$DOTFILES_SELECTION_FILE" ]] || return 1
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sel_add "$line"
  done < "$DOTFILES_SELECTION_FILE"
  return 0
}

selection_save() {
  mkdir -p "$DOTFILES_STATE_DIR"
  local i=0 line
  : > "$DOTFILES_SELECTION_FILE"
  while (( i < ITEM_N )); do
    if [[ "${ITEM_LOCKED[$i]}" != 1 ]] && sel_has "${ITEM_ID[$i]}"; then
      printf '%s\n' "${ITEM_ID[$i]}" >> "$DOTFILES_SELECTION_FILE"
    fi
    i=$((i + 1))
  done
}

# Compare two newline-delimited selections. Both are expected in the
# leading-sentinel form used by SELECTED, so membership is a simple substring.
selection_diff_added() { # old new
  local old="$1" new="$2" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$old" in
      *$'\n'"$line"$'\n'*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <<< "$new"
  return 0
}

selection_diff_removed() { # old new
  local old="$1" new="$2" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$new" in
      *$'\n'"$line"$'\n'*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <<< "$old"
  return 0
}

selection_ids_of_kind() { # ids kind
  local ids="$1" wanted="$2" line i
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    i="$(item_index "$line")" || continue
    if [[ "${ITEM_KIND[$i]}" == "$wanted" ]]; then printf '%s\n' "$line"; fi
  done <<< "$ids"
  return 0
}

# Render a Brewfile containing only the given ids and the taps they require.
# Used by --select so installing a newly selected package does not re-run the
# whole selected set.
selection_render_brewfile_ids() { # ids output
  local ids="$1" out="$2" line i kind name r tap seen=$'\n'
  {
    printf '# Generated for a selection delta — do not edit.\n'
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      i="$(item_index "$line")" || continue
      for r in ${ITEM_REQUIRES[$i]//,/ }; do
        case "$r" in
          tap:*)
            tap="tap \"${r#tap:}\""
            case "$seen" in
              *$'\n'"$tap"$'\n'*) ;;
              *) printf '%s\n' "$tap"; seen="$seen$tap"$'\n' ;;
            esac
            ;;
        esac
      done
    done <<< "$ids"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      i="$(item_index "$line")" || continue
      kind="${ITEM_KIND[$i]}"; name="${ITEM_NAME[$i]}"
      case "$kind" in
        brew|cask|vscode|npm) printf '%s "%s"\n' "$kind" "$name" ;;
      esac
    done <<< "$ids"
  } > "$out"
  return 0
}

# The selection file only records what is checked, so it cannot tell a newly
# added inventory item from one the user deliberately left unchecked. Keep a
# snapshot of every known item id and compare against it on the next run.
selection_inventory_current() {
  local i=0
  while (( i < ITEM_N )); do
    printf '%s\n' "${ITEM_ID[$i]}"
    i=$((i + 1))
  done
}

selection_write_inventory() {
  mkdir -p "$DOTFILES_STATE_DIR"
  selection_inventory_current > "$DOTFILES_INVENTORY_FILE"
}

selection_inventory_changed() {
  [[ -f "$DOTFILES_INVENTORY_FILE" ]] || return 0
  [[ "$(selection_inventory_current)" == "$(cat "$DOTFILES_INVENTORY_FILE")" ]] && return 1
  return 0
}

# Print the number of current items absent from the snapshot. Returns non-zero
# when there is no snapshot, so callers can fall back to a generic message.
selection_new_item_count() {
  [[ -f "$DOTFILES_INVENTORY_FILE" ]] || return 1
  local i=0 n=0
  while (( i < ITEM_N )); do
    grep -Fxq "${ITEM_ID[$i]}" "$DOTFILES_INVENTORY_FILE" 2>/dev/null \
      || n=$((n + 1))
    i=$((i + 1))
  done
  printf '%s' "$n"
}

selection_reset() {
  rm -f "$DOTFILES_SELECTION_FILE"
  SELECTED=$'\n'
}

selection_add_with_requires() { # id
  sel_add "$1"
  local i r
  i="$(item_index "$1")" || return 0
  for r in ${ITEM_REQUIRES[$i]//,/ }; do
    case "$r" in
      tap:*) continue ;;
      *) selection_add_with_requires "$r" ;;
    esac
  done
}

selection_prune_dependents() {
  local changed=1 i r
  while (( changed )); do
    changed=0
    i=0
    while (( i < ITEM_N )); do
      if [[ "${ITEM_LOCKED[$i]}" != 1 ]] && sel_has "${ITEM_ID[$i]}"; then
        for r in ${ITEM_REQUIRES[$i]//,/ }; do
          case "$r" in
            tap:*) continue ;;
          esac
          if ! sel_has "$r" && ! item_locked "$r"; then
            sel_del "${ITEM_ID[$i]}"
            changed=1
            break
          fi
        done
      fi
      i=$((i + 1))
    done
  done
}

selection_conflict_with() { # id -> conflicting id (either direction)
  local i c
  i="$(item_index "$1")" || return 1
  for c in ${ITEM_CONFLICTS[$i]//,/ }; do
    sel_has "$c" && { printf '%s' "$c"; return 0; }
  done
  i=0
  while (( i < ITEM_N )); do
    if sel_has "${ITEM_ID[$i]}"; then
      for c in ${ITEM_CONFLICTS[$i]//,/ }; do
        [[ "$c" == "$1" ]] && { printf '%s' "${ITEM_ID[$i]}"; return 0; }
      done
    fi
    i=$((i + 1))
  done
  return 1
}

selection_enable() { # id -> 0 enabled, 1 conflict, 2 unknown
  item_index "$1" >/dev/null || return 2
  local conflict
  if conflict="$(selection_conflict_with "$1")"; then
    SELECTION_LAST_CONFLICT="$conflict"
    return 1
  fi
  selection_add_with_requires "$1"
  return 0
}

selection_select_all() {
  SELECTED=$'\n'
  local i conflict
  i=0
  while (( i < ITEM_N )); do
    if [[ "${ITEM_LOCKED[$i]}" != 1 ]]; then
      if ! conflict="$(selection_conflict_with "${ITEM_ID[$i]}")"; then
        selection_add_with_requires "${ITEM_ID[$i]}"
      fi
    fi
    i=$((i + 1))
  done
}

selection_render_brewfile() {
  mkdir -p "$DOTFILES_STATE_DIR"
  local i kind name r seen=$'\n' line
  {
    printf '# Generated by scripts/lib-selection.sh from %s — do not edit.\n' "$DOTFILES_SELECTION_FILE"
    # Taps are dependencies, never user-selectable.
    i=0
    while (( i < ITEM_N )); do
      if [[ "${ITEM_LOCKED[$i]}" != 1 ]] && sel_has "${ITEM_ID[$i]}"; then
        for r in ${ITEM_REQUIRES[$i]//,/ }; do
          case "$r" in
            tap:*)
              line="tap \"${r#tap:}\""
              case "$seen" in *$'\n'"$line"$'\n'*) ;; *) printf '%s\n' "$line"; seen="$seen$line"$'\n' ;; esac
              ;;
          esac
        done
      fi
      i=$((i + 1))
    done
    i=0
    while (( i < ITEM_N )); do
      if [[ "${ITEM_LOCKED[$i]}" != 1 ]] && sel_has "${ITEM_ID[$i]}"; then
        kind="${ITEM_KIND[$i]}"; name="${ITEM_NAME[$i]}"
        case "$kind" in
          brew|cask|vscode|npm) line="$kind \"$name\"" ;;
          tap)                 line="tap \"$name\"" ;;
          *)                   i=$((i + 1)); continue ;;
        esac
        case "$seen" in
          *$'\n'"$line"$'\n'*) ;;
          *) printf '%s\n' "$line"; seen="$seen$line"$'\n' ;;
        esac
      fi
      i=$((i + 1))
    done
  } > "$DOTFILES_BREWFILE"
}

selection_render_ignore() {
  mkdir -p "$DOTFILES_STATE_DIR"
  : > "$DOTFILES_IGNORE_FILE"
  local i p
  i=0
  while (( i < ITEM_N )); do
    if [[ -n "${ITEM_PATHS[$i]}" ]]; then
      if [[ "${ITEM_LOCKED[$i]}" != 1 ]] && ! sel_has "${ITEM_ID[$i]}"; then
        for p in ${ITEM_PATHS[$i]//,/ }; do
          printf '%s\n' "$p" >> "$DOTFILES_IGNORE_FILE"
          # A trailing slash marks a directory; ignore its contents too.
          case "$p" in */) printf '%s**\n' "$p" >> "$DOTFILES_IGNORE_FILE" ;; esac
        done
      fi
    fi
    i=$((i + 1))
  done
}

selection_generate() {
  selection_prune_dependents
  selection_render_brewfile
  selection_render_ignore
}

selection_optional_count() {
  local i n=0
  i=0
  while (( i < ITEM_N )); do
    [[ "${ITEM_LOCKED[$i]}" != 1 ]] && n=$((n + 1))
    i=$((i + 1))
  done
  printf '%s' "$n"
}

selection_selected_count() {
  local i n=0
  i=0
  while (( i < ITEM_N )); do
    if [[ "${ITEM_LOCKED[$i]}" != 1 ]] && sel_has "${ITEM_ID[$i]}"; then n=$((n + 1)); fi
    i=$((i + 1))
  done
  printf '%s' "$n"
}

selection_validate() {
  local errors="" i c r
  i=0
  while (( i < ITEM_N )); do
    if [[ "${ITEM_LOCKED[$i]}" == 1 ]] || sel_has "${ITEM_ID[$i]}"; then
      for c in ${ITEM_CONFLICTS[$i]//,/ }; do
        sel_has "$c" && errors="$errors${ITEM_ID[$i]} conflicts with $c"$'\n'
      done
      for r in ${ITEM_REQUIRES[$i]//,/ }; do
        case "$r" in
          tap:*) continue ;;
        esac
        if ! sel_has "$r" && ! item_locked "$r"; then
          errors="$errors${ITEM_ID[$i]} requires $r"$'\n'
        fi
      done
    fi
    i=$((i + 1))
  done
  [[ -z "$errors" ]] && return 0
  printf '%s' "$errors"
  return 1
}

selection_prune_paths() { # [ids]
  local only_ids="${1:-}" i p target n=0
  [[ -n "$only_ids" ]] && only_ids=$'\n'"$only_ids"$'\n'
  i=0
  while (( i < ITEM_N )); do
    if [[ -n "${ITEM_PATHS[$i]}" ]] && [[ "${ITEM_LOCKED[$i]}" != 1 ]] \
       && ! sel_has "${ITEM_ID[$i]}"; then
      if [[ -n "$only_ids" ]]; then
        case "$only_ids" in
          *$'\n'"${ITEM_ID[$i]}"$'\n'*) ;;
          *) i=$((i + 1)); continue ;;
        esac
      fi
      for p in ${ITEM_PATHS[$i]//,/ }; do
        case "$p" in
          /*|*..*) printf 'skip unsafe path: %s\n' "$p" >&2; continue ;;
        esac
        target="$HOME/$p"
        if [[ -e "$target" || -L "$target" ]]; then
          rm -rf -- "$target" && n=$((n + 1))
        fi
      done
    fi
    i=$((i + 1))
  done
  printf '%s\n' "$n"
}

selection_config_ids() {
  local i
  i=0
  while (( i < ITEM_N )); do
    [[ "${ITEM_KIND[$i]}" == "config" ]] && printf '%s\n' "${ITEM_ID[$i]}"
    i=$((i + 1))
  done
}
