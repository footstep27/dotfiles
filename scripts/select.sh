#!/usr/bin/env bash
# Interactive checklist for the optional inventory.
#
#   ./scripts/select.sh             # edit and save ~/.local/state/dotfiles/selection
#   ./scripts/select.sh --readonly  # browse with the current/default state, save nothing
#
# Pure Bash on purpose: it must run on a bare Mac before Homebrew (and therefore
# before fzf, gum, or anything else) exists. It never installs or removes
# packages; bootstrap.sh turns the saved selection into a Brewfile and a
# .chezmoiignore fragment.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_ROOT="$ROOT"
# shellcheck source=lib-selection.sh
source "$ROOT/scripts/lib-selection.sh"

READONLY=0
for arg in "$@"; do
  case "$arg" in
    --readonly) READONLY=1 ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'select: unknown option %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [[ ! -t 0 || ! -t 1 ]]; then
  printf 'select: needs an interactive terminal\n' >&2
  exit 2
fi

selection_load_items
if ! selection_load_file; then
  selection_defaults
fi
selection_prune_dependents

BOLD=$'\033[1m'; DIM=$'\033[2m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'

# Read the real window size. `tput lines` cannot be used with its stderr
# redirected: ncurses then cannot query the terminal and reports the terminfo
# default (24) instead of the actual height, which caps the list at 19 rows.
HEIGHT="$(stty size 2>/dev/null | awk '{print $1}')"
case "$HEIGHT" in
  ''|*[!0-9]*) HEIGHT="$(tput lines 2>/dev/null || printf 24)" ;;
esac
(( HEIGHT < 10 )) && HEIGHT=10
COLS="$(stty size 2>/dev/null | awk '{print $2}')"
case "$COLS" in
  ''|*[!0-9]*) COLS="$(tput cols 2>/dev/null || printf 80)" ;;
esac
(( COLS < 20 )) && COLS=20

CUR=0
TOP=0
FILTER=""
MSG=""
SAVED_STTY=""

LINE_N=0; LINE_KIND=(); LINE_ITEM=(); LINE_TEXT=()

item_text() { # index
  local i="$1"
  case "${ITEM_KIND[$i]}" in
    config) printf '%s config' "${ITEM_NAME[$i]}" ;;
    *)      printf '%s' "${ITEM_NAME[$i]}" ;;
  esac
}

matches_filter() { # index
  [[ -z "$FILTER" ]] && return 0
  local needle hay
  needle="$(printf '%s' "$FILTER" | tr '[:upper:]' '[:lower:]')"
  hay="$(printf '%s %s %s %s' "${ITEM_NAME[$1]}" "${ITEM_ID[$1]}" "${ITEM_DESC[$1]}" \
    "$(cat_name "${ITEM_CAT[$1]}")" | tr '[:upper:]' '[:lower:]')"
  [[ "$hay" == *"$needle"* ]]
}

rebuild_lines() {
  LINE_N=0; LINE_KIND=(); LINE_ITEM=(); LINE_TEXT=()
  local i=0 lastcat=""
  while (( i < ITEM_N )); do
    if matches_filter "$i"; then
      if [[ "${ITEM_CAT[$i]}" != "$lastcat" ]]; then
        LINE_KIND[LINE_N]="H"
        LINE_ITEM[LINE_N]=-1
        LINE_TEXT[LINE_N]="$(cat_name "${ITEM_CAT[$i]}")"
        LINE_N=$((LINE_N + 1))
        lastcat="${ITEM_CAT[$i]}"
      fi
      LINE_KIND[LINE_N]="I"
      LINE_ITEM[LINE_N]=$i
      LINE_TEXT[LINE_N]="$(item_text "$i")"
      LINE_N=$((LINE_N + 1))
    fi
    i=$((i + 1))
  done
  if (( LINE_N == 0 )); then
    LINE_KIND[0]="H"; LINE_ITEM[0]=-1; LINE_TEXT[0]="no matches"; LINE_N=1
  fi
  (( CUR >= LINE_N )) && CUR=$((LINE_N - 1))
  (( CUR < 0 )) && CUR=0
  normalize_cur
}

normalize_cur() {
  if [[ "${LINE_KIND[$CUR]:-H}" == "I" ]]; then return 0; fi
  local c="$CUR"
  while (( c < LINE_N )); do
    [[ "${LINE_KIND[$c]}" == "I" ]] && { CUR=$c; return 0; }
    c=$((c + 1))
  done
  c=$((CUR - 1))
  while (( c >= 0 )); do
    [[ "${LINE_KIND[$c]}" == "I" ]] && { CUR=$c; return 0; }
    c=$((c - 1))
  done
  CUR=0
}

move_up() {
  local c=$((CUR - 1))
  while (( c >= 0 )); do
    [[ "${LINE_KIND[$c]}" == "I" ]] && { CUR=$c; return 0; }
    c=$((c - 1))
  done
}
move_down() {
  local c=$((CUR + 1))
  while (( c < LINE_N )); do
    [[ "${LINE_KIND[$c]}" == "I" ]] && { CUR=$c; return 0; }
    c=$((c + 1))
  done
}
move_first() {
  local c=0
  while (( c < LINE_N )); do
    [[ "${LINE_KIND[$c]}" == "I" ]] && { CUR=$c; return 0; }
    c=$((c + 1))
  done
}
focus_first_optional() {
  local c=0 ii
  while (( c < LINE_N )); do
    if [[ "${LINE_KIND[$c]}" == "I" ]]; then
      ii="${LINE_ITEM[$c]}"
      if [[ "${ITEM_LOCKED[$ii]}" != 1 ]]; then CUR=$c; return 0; fi
    fi
    c=$((c + 1))
  done
  move_first
}
move_last() {
  local c=$((LINE_N - 1))
  while (( c >= 0 )); do
    [[ "${LINE_KIND[$c]}" == "I" ]] && { CUR=$c; return 0; }
    c=$((c - 1))
  done
}

draw() {
  local rows=$((HEIGHT - 5))
  (( rows < 1 )) && rows=1
  if (( CUR < TOP )); then TOP=$CUR; fi
  if (( CUR >= TOP + rows )); then TOP=$((CUR - rows + 1)); fi
  (( TOP < 0 )) && TOP=0
  if (( TOP > LINE_N - rows )); then TOP=$((LINE_N - rows)); fi
  (( TOP < 0 )) && TOP=0

  printf '\033[?25l\033[H\033[2J'
  printf '%sdotfiles optional inventory%s\n' "$BOLD" "$RESET"
  printf '%s↑/↓ move  space toggle  a/n category  A/N all  / filter  enter save  q cancel%s\n' "$DIM" "$RESET"
  if [[ -n "$FILTER" ]]; then
    printf '%sfilter: %s%s\n' "$YELLOW" "$FILTER" "$RESET"
  else
    printf '\n'
  fi

  local l=$TOP end=$((TOP + rows))
  (( end > LINE_N )) && end=$LINE_N
  while (( l < end )); do
    if [[ "${LINE_KIND[$l]}" == "H" ]]; then
      printf '%s── %s ──%s\n' "$BOLD" "${LINE_TEXT[$l]}" "$RESET"
    else
      local ii="${LINE_ITEM[$l]}" mark="[ ]" note=""
      local text="${LINE_TEXT[$l]}" desc="${ITEM_DESC[$ii]:-}"
      if [[ "${ITEM_LOCKED[$ii]}" == 1 ]]; then
        mark="[x]"; note="  (required)"
      elif sel_has "${ITEM_ID[$ii]}"; then
        mark="[x]"
      fi
      # Keep every item on one row: trim the description to whatever space is
      # left after the mark, the name and the required note.
      local room=$((COLS - 4 - ${#note}))
      (( room < 8 )) && room=8
      if (( ${#text} >= room )); then
        text="${text:0:room}"
        desc=""
      elif [[ -n "$desc" ]]; then
        local space=$((room - ${#text} - 3))
        if (( space < 8 )); then
          desc=""
        elif (( ${#desc} > space )); then
          desc="${desc:0:space-3}"
          desc="${desc% *}..."
        fi
      fi
      if (( l == CUR )); then
        local body="$text"
        [[ -n "$desc" ]] && body="$body - $desc"
        printf '\033[7m%s %s%s\033[0m\n' "$mark" "$body" "$note"
      else
        printf '%s %s' "$mark" "$text"
        [[ -n "$desc" ]] && printf ' %s- %s%s' "$DIM" "$desc" "$RESET"
        printf '%s\n' "$note"
      fi
    fi
    l=$((l + 1))
  done

  printf '\033[%d;1H\033[2K' "$HEIGHT"
  printf 'selected %s/%s' "$(selection_selected_count)" "$(selection_optional_count)"
  [[ -n "$MSG" ]] && printf '  %s%s%s' "$YELLOW" "$MSG" "$RESET"
  printf '\033[?25h'
}

toggle_current() {
  local ii="${LINE_ITEM[$CUR]}"
  if [[ "$ii" == "-1" ]]; then return 0; fi
  if [[ "${ITEM_LOCKED[$ii]}" == 1 ]]; then
    MSG="required — always installed"
    return 0
  fi
  local id="${ITEM_ID[$ii]}"
  if sel_has "$id"; then
    sel_del "$id"
    selection_prune_dependents
    MSG="unselected $id"
  else
    selection_enable "$id"
    case $? in
      0) MSG="selected $id" ;;
      1) MSG="conflicts with ${SELECTION_LAST_CONFLICT}" ;;
      *) MSG="unknown item $id" ;;
    esac
  fi
}

category_action() { # add|remove
  local ii="${LINE_ITEM[$CUR]}" cat id n=0 conflict
  [[ "$ii" == "-1" ]] && return 0
  cat="${ITEM_CAT[$ii]}"
  local i=0
  while (( i < ITEM_N )); do
    if [[ "${ITEM_CAT[$i]}" == "$cat" && "${ITEM_LOCKED[$i]}" != 1 ]]; then
      id="${ITEM_ID[$i]}"
      if [[ "$1" == "add" ]]; then
        if ! sel_has "$id" && ! conflict="$(selection_conflict_with "$id")"; then
          selection_add_with_requires "$id"
          n=$((n + 1))
        fi
      else
        if sel_has "$id"; then sel_del "$id"; n=$((n + 1)); fi
      fi
    fi
    i=$((i + 1))
  done
  [[ "$1" == "remove" ]] && selection_prune_dependents
  MSG="$1 category: $n item(s)"
}

all_action() { # add|remove
  if [[ "$1" == "add" ]]; then
    selection_select_all
    MSG="selected every non-conflicting item"
  else
    SELECTED=$'\n'
    MSG="cleared every optional item"
  fi
}

filter_prompt() {
  stty "$SAVED_STTY" 2>/dev/null || true
  printf '\033[%d;1H\033[2K' "$HEIGHT"
  printf 'filter (empty clears): '
  IFS= read -r FILTER
  stty -echo -icanon min 1 time 0
  rebuild_lines
  CUR=0
  normalize_cur
  focus_first_optional
  TOP=0
  MSG=""
}

read_key() {
  KEY=""
  IFS= read -rsn1 KEY
  if [[ "$KEY" == $'\033' ]]; then
    local k2="" k3=""
    # Bash 3.2 (the system bash on macOS) rejects fractional -t values.
    IFS= read -rsn1 -t 1 k2 || { KEY="ESC"; return 0; }
    if [[ "$k2" == '[' ]]; then
      IFS= read -rsn1 -t 1 k3 || { KEY="ESC"; return 0; }
      case "$k3" in
        A) KEY="UP" ;;
        B) KEY="DOWN" ;;
        H) KEY="HOME" ;;
        F) KEY="END" ;;
        *) KEY="ESC" ;;
      esac
    else
      KEY="ESC"
    fi
  fi
}

cleanup() {
  [[ -n "$SAVED_STTY" ]] && stty "$SAVED_STTY" 2>/dev/null || true
  printf '\033[?25h\n'
}
trap cleanup EXIT INT TERM

SAVED_STTY="$(stty -g)"
stty -echo -icanon min 1 time 0

rebuild_lines
CUR=0
normalize_cur
focus_first_optional
draw

while :; do
  read_key
  MSG=""
  case "$KEY" in
    UP|k)    move_up ;;
    DOWN|j)  move_down ;;
    HOME|g)  move_first ;;
    END|G)   move_last ;;
    ' ')     toggle_current ;;
    a)       category_action add ;;
    n)       category_action remove ;;
    A)       all_action add ;;
    N)       all_action remove ;;
    /)       filter_prompt ;;
    ''|$'\r'|$'\n')      # enter
      if selection_validate >/dev/null; then
        if (( READONLY )); then
          MSG="read-only: nothing saved"
          break
        fi
        selection_generate
        selection_save
        break
      else
        MSG="selection has unresolved dependencies"
      fi
      ;;
    q|Q|ESC) exit 130 ;;
  esac
  draw
done

cleanup
if (( READONLY )); then
  printf 'Read-only: %s selected of %s optional items. Nothing saved.\n' \
    "$(selection_selected_count)" "$(selection_optional_count)"
else
  printf 'Saved %s of %s optional items to %s\n' \
    "$(selection_selected_count)" "$(selection_optional_count)" "$DOTFILES_SELECTION_FILE"
fi
