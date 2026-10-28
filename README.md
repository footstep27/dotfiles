# dotfiles

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/repo-overview-dark.svg">
  <img src="docs/diagrams/repo-overview.svg" alt="Architecture: edits go into the dotfiles repo, chezmoi apply copies them into live configs under the home directory, and the terminal apps read them. A dashed path shows bootstrap.sh as the one-time setup for a new machine." width="960">
</picture>

Personal macOS setup as code: Ghostty, zsh + powerlevel10k, tmux, WezTerm, yazi, btop, git,
and the fonts and packages they need. Managed with [chezmoi](https://www.chezmoi.io/).

This repository **is** the chezmoi source. `$HOME` holds copies — not symlinks — so edits
belong here, and one command puts them on the machine.

Setting up a fresh Mac? [Jump to the bootstrap steps](#new-machine). Otherwise the loop below
is all you need.

## Daily work

Four commands cover almost everything:

| I want to… | Run |
|---|---|
| edit a managed file | `chezmoi edit ~/.zshrc` |
| see what would change | `chezmoi diff` |
| make the machine match the repo | `chezmoi apply` |
| jump into the source repo | `chezmoi cd` |

A normal change is short:

```sh
chezmoi edit ~/.config/ghostty/config   # opens the repo copy, not the live file
chezmoi diff                            # review before writing anything
chezmoi apply                           # copy it into $HOME
git -C ~/Repositories/dotfiles commit -am "ghostty: font size 13"
```

Some changes only land after the app reloads:

| App | Reload |
|---|---|
| Ghostty | `⌘⌃,` (reload config) or open a new window |
| zsh | `exec zsh` |
| tmux | `tmux source-file ~/.tmux.conf` |
| yazi, btop | relaunch |

### The one rule

**Edit the repo, not `$HOME`.** `chezmoi apply` overwrites live files with no prompt. If you
already edited a live file by accident, pull it into the repo instead of applying:

```sh
chezmoi add ~/.zshrc     # one file: live → repo
chezmoi re-add           # all drifted managed files: live → repo
chezmoi status           # one line per managed file that differs
```

Look at `chezmoi diff` before `apply`. That diff *is* the review step.

## Keeping it up to date

Changes travel through git:

```sh
# on the machine where you made the change
git -C ~/Repositories/dotfiles push

# on every other machine
chezmoi update            # git pull + chezmoi apply
```

`chezmoi update` stops if the pull fails, so a conflict never half-applies. Resolve it in the
repo with normal git commands, then run `chezmoi apply`.

If the other machine has local drift you care about, pull it in before updating:

```sh
chezmoi diff              # what would be overwritten
chezmoi re-add            # keep the local edits
git -C ~/Repositories/dotfiles commit -am "capture local changes"
chezmoi update
```

Package updates are separate:

```sh
brew bundle check  --file="$HOME/Repositories/dotfiles/Brewfile"
brew bundle install --file="$HOME/Repositories/dotfiles/Brewfile"
```

`Brewfile` is the required set; `Brewfile.optional` is a snapshot of everything else and is
installed only on request.

## Adding something new

```sh
chezmoi add ~/.config/foo/config    # track a live file (writes dot_config/foo/config here)
chezmoi add --secrets error ~/.foo  # same, but abort instead of warning on secret-like content
chezmoi add --encrypt ~/.secret     # age-encrypted source file
```

Rules for this repo:

- Anything that should land in `$HOME` belongs in the source tree as `dot_*` / `dot_config/…`.
- Anything repo-only (docs, scripts, project skills, manifests) must be listed in
  `.chezmoiignore` — `docs/`, `scripts/`, `.opencode/`, `README.md`, and the Brewfiles already are.
- Prefer `--secrets error` when adding files. `verify.sh` also fails if a known secret or
  state path becomes managed.
- Encryption is wired (age) but idle. Back up `~/.config/chezmoi/key.txt` before the first
  secret depends on it; a new machine cannot decrypt without it.

Global agent skills are installed and updated by the skills CLI, which writes
`~/.agents/skills` and `.skill-lock.json`. Both are managed here, so after adding or updating
skills run `chezmoi re-add ~/.agents`, review, commit, and push.

## New machine

```sh
git clone git@github.com:footstep27/dotfiles.git ~/Repositories/dotfiles
cd ~/Repositories/dotfiles
./bootstrap.sh --dry-run     # see the plan
./bootstrap.sh
```

`bootstrap.sh` is idempotent and runs, in order: Homebrew (installing it if absent) →
`Brewfile` → chezmoi source wiring (including the age recipient) → archive of managed
dotfiles when any drifted → `chezmoi apply` → Ghostty terminfo → tmux plugins at their pinned
refs → `scripts/verify.sh`.

The archive lands in `~/.dotfiles-backup-<timestamp>/dotfiles.tar.gz`; restore it with
`tar -xzf … -C /`. Later runs only archive when local files have drifted from the repo.

## What this repo owns

| Area | Managed |
|---|---|
| Shell | `.zshrc`, `.zprofile`, `.zshenv`, `.p10k.zsh`, legacy `.tcshrc` and `.profile` |
| Ghostty | `~/.config/ghostty/config` |
| tmux | `.tmux.conf` (plugins pinned here, installed via TPM) |
| WezTerm | `.wezterm.lua` + the one theme file actually used |
| TUIs | `yazi` config, `btop` config and its Catppuccin Mocha theme |
| Fonts | the licensed MonoLisa pair (see `docs/fonts.md`) |
| Git | global `.gitconfig` |
| OpenCode | `~/.config/opencode/cli.json` (theme, diffs, session UI) and `opencode.jsonc` (global config) |
| Agent skills | global `~/.agents/skills` + `.skill-lock.json`; the project skill lives in `.opencode/skills/diagram-design/` (repo-only) |
| Packages | `Brewfile` (required), `Brewfile.optional` (snapshot, installed on request) |

Deliberately **not** managed: credentials (GPG keys, `gh`), OpenCode secrets and state
(`~/.local/share/opencode/auth.json`, both `service.json` files, `opencode.db*`, plugin
`node_modules`), nvim config, shell histories, Oh My Zsh (Homebrew-vendored), tmux plugin
trees, the WezTerm theme repository clone, `yazi` flavors/plugins.

Those OpenCode paths are listed in `.chezmoiignore` as guards, and `verify.sh` fails if any of
them ever ends up in the source.

`~/.vim` contains only netrw's history file, so it stays unmanaged. If it ever gets real
config, `chezmoi add` it.

## Verifying

```sh
./scripts/verify.sh
```

One row per check, `pass` / `warn` / `FAIL`; exit status is non-zero only on failure. It
asserts behaviour, not file contents: the Ghostty config parses, text and icon faces resolve,
zsh loads cleanly through a pty, tmux starts with every plugin at its pinned ref, and the
Brewfile is satisfied.

## Two steps that stay manual

1. **Default terminal app.** macOS has no dependable CLI for this. Set Ghostty as the default
   in System Settings (or via Finder's "Open With"). iTerm2 and WezTerm stay installed as
   fallbacks.
2. **MonoLisa, if missing.** Licensed software, so no Homebrew formula. `verify.sh` reports a
   warning and the terminals fall back through the font chain. See `docs/fonts.md`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| A change disappeared after `apply` | `apply` overwrote the live file. Edit the repo; if the live edit was the good one, `chezmoi re-add` first. |
| Prompt or glyphs look wrong | Check the MonoLisa step above, run `./scripts/verify.sh`, read `docs/fonts.md`. |
| `xterm-ghostty` unknown over ssh | Rerun `./bootstrap.sh` (copies the bundled terminfo) and check with `infocmp -x xterm-ghostty`. |
| `sourceDir` points at another checkout | Fix `~/.config/chezmoi/chezmoi.toml` so it names this repo, or rerun `bootstrap.sh`. |
| tmux plugins missing | `bash ~/.tmux/plugins/tpm/bin/install_plugins`, or rerun `./bootstrap.sh`. |
| Want to see the plan first | `chezmoi apply --dry-run --verbose` |

## Layout

```
bootstrap.sh            fresh-machine entry point (--dry-run supported)
scripts/verify.sh       behaviour checks for the applied machine
Brewfile                required packages
Brewfile.optional       snapshot of the rest of the inventory
dot_* / dot_config/     chezmoi-managed configs (names map to $HOME)
dot_agents/             global agent skills + lockfile (chezmoi-managed)
dot_tmux.conf           tmux, including pinned plugin refs
.opencode/skills/       project skill, repo-only (chezmoi-ignored)
docs/                   fonts, themes, decisions, diagram sources
```

The README diagram is generated, not hand-drawn: edit `docs/diagrams/repo-overview.html`
(and `-dark.html`), then re-export with the diagram-design skill:

```sh
python3 .opencode/skills/diagram-design/scripts/export_svg.py \
  docs/diagrams/repo-overview.html docs/diagrams/repo-overview.svg --system-fonts
```

## Why it's built this way

- **The repo is the chezmoi source,** and age is the chosen encryption backend. Reasoning in
  [`docs/adr/0001-chezmoi-and-age.md`](docs/adr/0001-chezmoi-and-age.md). age is wired but
  idle: `bootstrap.sh` generates an identity and records the recipient; no file is encrypted.
- **Option stays a character key** on the German layout (`macos-option-as-alt = false`).
  Option types `@ { } [ ] | \ ~ €`; word movement lives on `Ctrl+Left/Right` and
  `Ctrl+Backspace`, bound in `.zshrc`.
- **The theme is fixed Mocha, not system-following.** tmux cannot observe the macOS appearance
  switch, so the status bar stays Mocha; `window-theme = dark` keeps the frame matching.
  See [`docs/themes.md`](docs/themes.md) for switching.
- **tmux is for persistence, not splitting.** Long-running work in named sessions; quick
  side-by-side work in Ghostty's native splits. Scrollback is capped at 10,000 lines and
  window restore is off because tmux owns persistence.
- **MonoLisa ships as a variable pair** (no separate Bold), so bold is synthesized. The escape
  hatch is putting `MesloLGS NF` ahead of it in the Ghostty font list.
- **`tmux-cpu` is pinned to a commit, not a tag** — the only plugin whose upstream publishes
  no tags (`#bcb110d`).
- **`core.editor` is deliberately unset.** Interactive committing goes through `lazygit`.
