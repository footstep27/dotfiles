# shellcheck shell=bash
# Shared model for agent skills that live outside this repository.
#
# scripts/skills.conf declares one floating upstream per line:
#
#   owner/repo  branch  include-dir[,include-dir...]
#
# bootstrap.sh clones each upstream under ~/.local/share/dotfiles/upstreams/
# and links every directory containing SKILL.md into ~/.agents/skills. The
# clones are canonical; the links are disposable. verify.sh reads the same
# manifest and checks the links without mutating anything.
#
# Nothing here prints user-facing text. Operations set SKILLS_* globals and
# append `level<TAB>message` lines to SKILLS_REPORT so bootstrap can format them
# with its own step/info/warn helpers.

DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SKILLS_CONF="${SKILLS_CONF:-$DOTFILES_ROOT/scripts/skills.conf}"
SKILLS_UPSTREAM_DIR="${SKILLS_UPSTREAM_DIR:-$HOME/.local/share/dotfiles/upstreams}"
SKILLS_TARGET_DIR="${SKILLS_TARGET_DIR:-$HOME/.agents/skills}"

SKILLS_REPORT=""
SKILLS_MIGRATED=""
SKILLS_BACKUP_DIR=""
SKILLS_CONF_ERRORS=""

# Sync result for one upstream: cloned | updated | current | dirty | failed
SKILLS_SYNC_STATUS=""
SKILLS_SYNC_BEFORE=""
SKILLS_SYNC_AFTER=""

# Parallel arrays: Bash 3.2 on macOS has no associative arrays.
UP_N=0
UP_REPO=(); UP_BRANCH=(); UP_INCLUDES=()

skills_report() { # level message
  SKILLS_REPORT="$SKILLS_REPORT$1"$'\t'"$2"$'\n'
}

skills_load_upstreams() {
  UP_N=0; UP_REPO=(); UP_BRANCH=(); UP_INCLUDES=()
  SKILLS_CONF_ERRORS=""

  if [[ ! -f "$SKILLS_CONF" ]]; then
    SKILLS_CONF_ERRORS="missing $SKILLS_CONF"
    return 1
  fi

  local line repo branch includes
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim surrounding whitespace, then ignore blank lines and comments.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      ""|\#*) continue ;;
    esac

    repo=""; branch=""; includes=""
    read -r repo branch includes <<< "$line"
    if [[ -z "$repo" || -z "$branch" || -z "$includes" || "$repo" != */* ]]; then
      SKILLS_CONF_ERRORS="$SKILLS_CONF_ERRORS$line"$'\n'
      continue
    fi

    UP_REPO[UP_N]="$repo"
    UP_BRANCH[UP_N]="$branch"
    UP_INCLUDES[UP_N]="$includes"
    UP_N=$((UP_N + 1))
  done < "$SKILLS_CONF"

  if (( UP_N == 0 )); then
    SKILLS_CONF_ERRORS="${SKILLS_CONF_ERRORS}no upstreams declared"$'\n'
  fi
  [[ -z "$SKILLS_CONF_ERRORS" ]]
}

skills_repo_url() { # owner/repo
  printf 'https://github.com/%s.git' "$1"
}

skills_checkout_dir() { # owner/repo
  printf '%s/%s' "$SKILLS_UPSTREAM_DIR" "$1"
}

# Print absolute paths of every directory directly under an include that holds
# a SKILL.md. One level deep is the Agent Skills convention; a skill's own
# references and assets stay inside that directory and travel with the link.
skills_skill_dirs() { # owner/repo includes
  local repo="$1" includes="$2" include dir
  local IFS=','
  for include in $includes; do
    for dir in "$(skills_checkout_dir "$repo")/$include"/*/; do
      [[ -f "${dir}SKILL.md" ]] && printf '%s\n' "${dir%/}"
    done
  done
}

# Bring one checkout to the upstream branch. A dirty checkout is never touched:
# upstream invites people to hack on these files, so local work always wins.
# Sets SKILLS_SYNC_STATUS and the before/after short SHAs; always returns 0 so
# one broken upstream cannot abort the whole bootstrap.
skills_sync_checkout() { # owner/repo branch
  local repo="$1" branch="$2" dir url sha
  dir="$(skills_checkout_dir "$repo")"
  url="$(skills_repo_url "$repo")"
  SKILLS_SYNC_STATUS=""
  SKILLS_SYNC_BEFORE=""
  SKILLS_SYNC_AFTER=""

  if [[ ! -d "$dir/.git" ]]; then
    # A non-empty directory that is not a checkout cannot be cloned into.
    if [[ -e "$dir" ]]; then
      SKILLS_SYNC_STATUS="failed"
      return 0
    fi
    mkdir -p "$(dirname "$dir")" || { SKILLS_SYNC_STATUS="failed"; return 0; }
    if git clone --quiet --depth 1 --branch "$branch" "$url" "$dir" 2>/dev/null; then
      SKILLS_SYNC_STATUS="cloned"
      SKILLS_SYNC_AFTER="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
    else
      SKILLS_SYNC_STATUS="failed"
    fi
    return 0
  fi

  SKILLS_SYNC_BEFORE="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
  SKILLS_SYNC_AFTER="$SKILLS_SYNC_BEFORE"

  # Generated or downloaded files are normal; only tracked modifications count
  # as "do not touch this", matching ensure_pinned_repo in bootstrap.sh.
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    SKILLS_SYNC_STATUS="dirty"
    return 0
  fi

  if ! git -C "$dir" fetch --quiet --depth 1 origin "$branch" 2>/dev/null; then
    SKILLS_SYNC_STATUS="failed"
    return 0
  fi

  sha="$(git -C "$dir" rev-parse FETCH_HEAD 2>/dev/null)"
  if [[ "$sha" == "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" ]]; then
    SKILLS_SYNC_STATUS="current"
    return 0
  fi

  # The tree is clean, so a hard reset only moves tracked files to the fetched
  # tip. Untracked files are left in place: they may be the user's own notes.
  if git -C "$dir" reset --quiet --hard FETCH_HEAD 2>/dev/null; then
    SKILLS_SYNC_STATUS="updated"
    SKILLS_SYNC_AFTER="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
  else
    SKILLS_SYNC_STATUS="failed"
  fi
  return 0
}

# One backup directory per run, created lazily so a healthy machine never gets
# an empty backup directory. The timestamp keeps repeated migrations apart.
skills_ensure_backup_dir() {
  [[ -n "$SKILLS_BACKUP_DIR" ]] && return 0
  local base n=1
  base="$HOME/.agents/skills.pre-checkout-$(date +%Y%m%d-%H%M%S)"
  SKILLS_BACKUP_DIR="$base"
  while [[ -e "$SKILLS_BACKUP_DIR" ]]; do
    SKILLS_BACKUP_DIR="$base-$n"
    n=$((n + 1))
  done
  mkdir -p "$SKILLS_BACKUP_DIR"
}

# Back up anything already sitting at the target name: an old vendored
# directory, a file, or a foreign symlink. A link owned by this mechanism is
# simply replaced. The second argument lets the lockfile reuse the same rules.
skills_backup_path() { # target backup-name
  local target="$1" name="$2"
  [[ -e "$target" || -L "$target" ]] || return 0

  if [[ -L "$target" ]]; then
    case "$(readlink "$target")" in
      "$SKILLS_UPSTREAM_DIR"/*) rm -f "$target"; return 0 ;;
    esac
  fi

  skills_ensure_backup_dir || return 1
  mv -- "$target" "$SKILLS_BACKUP_DIR/$name" || return 1
  SKILLS_MIGRATED="$SKILLS_MIGRATED$name"$'\n'
}

skills_migrate_lockfile() {
  local lockfile="$HOME/.agents/.skill-lock.json"
  [[ -e "$lockfile" || -L "$lockfile" ]] || return 0
  skills_backup_path "$lockfile" ".skill-lock.json"
}

skills_link_dir() { # name source
  local name="$1" source="$2" target="$SKILLS_TARGET_DIR/$1"
  skills_backup_path "$target" "$name" || {
    skills_report warn "could not back up $target"
    return 1
  }
  ln -sfn "$source" "$target" || {
    skills_report warn "could not link $name"
    return 1
  }
}

# Remove links into our checkouts that the manifest no longer declares, and
# links that stopped resolving when an upstream renamed or deleted a skill.
# Foreign links are left alone: they are not ours to manage.
skills_prune_links() { # desired names, newline-wrapped
  local desired="$1" entry dest name
  [[ -d "$SKILLS_TARGET_DIR" ]] || return 0
  for entry in "$SKILLS_TARGET_DIR"/*; do
    [[ -L "$entry" ]] || continue
    dest="$(readlink "$entry")"
    case "$dest" in
      "$SKILLS_UPSTREAM_DIR"/*) ;;
      *) continue ;;
    esac
    name="$(basename "$entry")"
    case "$desired" in
      *$'\n'"$name"$'\n'*)
        if [[ ! -e "$dest" ]]; then
          rm -f "$entry" && skills_report info "pruned stale link $name"
        fi
        ;;
      *)
        rm -f "$entry" && skills_report info "pruned link $name (no longer declared)"
        ;;
    esac
  done
}

# Sync every checkout, then link every skill. With a non-zero argument, change
# nothing and report what a real run would do. On a name collision the first
# upstream in skills.conf wins, deterministically.
skills_install() { # dry(0|1)
  local dry="$1" i repo branch includes name source seen entry count checkout
  SKILLS_REPORT=""
  SKILLS_MIGRATED=""
  SKILLS_BACKUP_DIR=""

  if ! skills_load_upstreams; then
    skills_report warn "scripts/skills.conf: ${SKILLS_CONF_ERRORS//$'\n'/; }"
    return 1
  fi

  if (( dry )); then
    i=0
    while (( i < UP_N )); do
      repo="${UP_REPO[$i]}"; branch="${UP_BRANCH[$i]}"
      checkout="$(skills_checkout_dir "$repo")"
      if [[ -d "$checkout/.git" ]]; then
        if [[ -n "$(git -C "$checkout" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
          skills_report warn "$repo has local changes — would leave it alone"
        else
          skills_report info "would update $repo ($branch) and relink its skills"
        fi
      else
        skills_report info "would clone $repo ($branch)"
      fi
      i=$((i + 1))
    done
    if [[ -d "$SKILLS_TARGET_DIR" ]]; then
      count=0
      for entry in "$SKILLS_TARGET_DIR"/*; do
        [[ -L "$entry" ]] || count=$((count + 1))
      done
      (( count > 0 )) && skills_report info "would back up any conflicting entries before linking"
    fi
    return 0
  fi

  mkdir -p "$SKILLS_TARGET_DIR" "$SKILLS_UPSTREAM_DIR" || {
    skills_report warn "could not create $SKILLS_TARGET_DIR or $SKILLS_UPSTREAM_DIR"
    return 1
  }

  # Sync first, so links are created against the final content of every clone.
  i=0
  while (( i < UP_N )); do
    repo="${UP_REPO[$i]}"; branch="${UP_BRANCH[$i]}"
    skills_sync_checkout "$repo" "$branch"
    case "$SKILLS_SYNC_STATUS" in
      cloned)  skills_report info "$repo cloned at $SKILLS_SYNC_AFTER" ;;
      updated) skills_report info "$repo moved $SKILLS_SYNC_BEFORE -> $SKILLS_SYNC_AFTER" ;;
      current) skills_report info "$repo already at $SKILLS_SYNC_AFTER" ;;
      dirty)   skills_report warn "$repo has local changes — left alone" ;;
      failed)  skills_report warn "$repo could not be fetched" ;;
    esac
    i=$((i + 1))
  done

  i=0
  seen=$'\n'
  while (( i < UP_N )); do
    repo="${UP_REPO[$i]}"; includes="${UP_INCLUDES[$i]}"
    while IFS= read -r source; do
      [[ -n "$source" ]] || continue
      name="$(basename "$source")"
      case "$seen" in
        *$'\n'"$name"$'\n'*)
          skills_report warn "duplicate skill '$name' in $repo — keeping the first"
          continue
          ;;
      esac
      seen="$seen$name"$'\n'
      skills_link_dir "$name" "$source" || true
    done < <(skills_skill_dirs "$repo" "$includes")
    i=$((i + 1))
  done

  skills_migrate_lockfile
  skills_prune_links "$seen"

  if [[ -n "$SKILLS_MIGRATED" ]]; then
    skills_report info "migrated existing entries to $SKILLS_BACKUP_DIR"
  fi
  return 0
}
