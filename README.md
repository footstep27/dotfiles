# dotfiles

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/repo-overview-dark.svg">
  <img src="docs/diagrams/repo-overview.svg" alt="Architecture: edits go into the dotfiles repo, chezmoi apply copies them into live configs under the home directory, and the terminal apps read them. A dashed path shows bootstrap.sh as the one-time setup for a new machine." width="960">
</picture>

Personal macOS setup as code: Ghostty, zsh + powerlevel10k, tmux, WezTerm, yazi, btop, git,
and the fonts and packages they need. Managed with [chezmoi](https://www.chezmoi.io/).

This repository **is** the chezmoi source. `$HOME` holds copies — not symlinks — so edits
belong here, and one command puts them on the machine.

**The goal is one thing: a genuinely bare Mac — stock macOS, an admin user, a network
connection, no Command Line Tools, no Homebrew, no git — becoming this exact setup.** That
is the standard every change here is measured against, and `scripts/verify.sh` is how it is
proved. Setting up such a machine? [Jump to the bootstrap steps](#new-machine).

If you are not me, the configs are readable but they are not a template: change the identity
in `.gitconfig`, install your own fonts, and expect no support. There is no promise that
today's checkout applies cleanly next month.

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

A bare Mac has no `git`, no compiler and therefore no Homebrew, so the first two steps stay
manual:

```sh
xcode-select --install                                     # GUI dialog; click through it
git clone https://github.com/footstep27/dotfiles.git ~/Repositories/dotfiles
cd ~/Repositories/dotfiles
./bootstrap.sh --dry-run     # see the plan
./bootstrap.sh
```

HTTPS on purpose: a bare machine has no SSH key yet.

`bootstrap.sh` is idempotent and runs, in order: Command Line Tools pre-flight → Homebrew
(installing it if absent) → `Brewfile` → chezmoi source wiring (including the age recipient)
→ archive of managed dotfiles when any drifted → `chezmoi apply` → Oh My Zsh and
powerlevel10k at their pinned commits → Ghostty terminfo → tmux plugins at their pinned refs
→ yazi packages → `scripts/verify.sh`.

The archive lands in `~/.dotfiles-backup-<timestamp>/dotfiles.tar.gz`; restore it with
`tar -xzf … -C /`. Later runs only archive when local files have drifted from the repo.

## What this repo owns

| Area | Managed |
|---|---|
| Shell | `.zshrc`, `.zprofile`, `.zshenv`, `.p10k.zsh`, legacy `.tcshrc` and `.profile` |
| Ghostty | `~/.config/ghostty/config` |
| tmux | `.tmux.conf` (plugins pinned here, installed via TPM) |
| WezTerm | `.wezterm.lua` + the one theme file actually used |
| TUIs | `yazi` config, `btop` config and its Catppuccin Macchiato theme |
| Fonts | nothing managed — install your own licensed MonoLisa (see `docs/fonts.md`) |
| Git | global `.gitconfig` |
| OpenCode | `~/.config/opencode/cli.json` (theme, diffs, session UI) and `opencode.jsonc` (global config) |
| Agent skills | global `~/.agents/skills` + `.skill-lock.json`; the project skill lives in `.opencode/skills/diagram-design/` (repo-only) |
| Packages | `Brewfile` (required), `Brewfile.optional` (snapshot, installed on request) |

Deliberately **not** managed: credentials (GPG keys, `gh`), OpenCode secrets and state
(`~/.local/share/opencode/auth.json`, both `service.json` files, `opencode.db*`, plugin
`node_modules`), nvim config, shell histories, Oh My Zsh (Homebrew-vendored), tmux plugin
trees, the WezTerm theme repository clone, `yazi` flavors/plugins (declared in
`package.toml` and restored with `ya pkg install`).

Those OpenCode paths are listed in `.chezmoiignore` as guards, and `verify.sh` fails if any of
them ever ends up in the source.

`~/.vim` contains only netrw's history file, so it stays unmanaged. If it ever gets real
config, `chezmoi add` it.

## What a fresh machine gets

`./bootstrap.sh` installs the required Homebrew set, copies the configs below into `$HOME`,
then installs tmux plugins and yazi packages from their own upstreams. `Brewfile.optional`
is **not** part of that run: it is a snapshot of everything else on this machine, installed
on request.

### Packages

| Tool | What it does here |
|---|---|
| **chezmoi** | Copies the tracked configs into `$HOME` and shows drift before it writes. |
| **age** | Encryption backend for chezmoi; `bootstrap.sh` generates an identity, though nothing is encrypted today. |
| **tmux** | Multiplexer that owns session persistence, with plugins and a pinned status bar. |
| **btop** | TUI system monitor, themed Catppuccin Macchiato. |
| **eza** | `ls` replacement aliased to `eza --icons`, so file types show as glyphs. |
| **bat** | `cat` replacement with syntax highlighting, aliased as `cat` only when the binary exists. |
| **git-delta** | Side-by-side diff pager wired into `git diff` and `git log` through `~/.gitconfig`. |
| **lazygit** | TUI git client on `lg`, and the reason `core.editor` is deliberately unset. |
| **yazi** | Terminal file manager behind the `y` wrapper that changes directory on exit. |
| **zsh-autosuggestions** | Fish-style history suggestions while typing; sourced by `.zshrc`. |
| **zsh-syntax-highlighting** | Command-line colouring as you type; sourced last so it can see the line. |
| **opencode** | Agent CLI whose config in `~/.config/opencode` is managed here. |
| **Ghostty** | Default terminal; the config fixes the Macchiato theme, MonoLisa plus symbol fallback, splits, quick terminal and command-finish notifications. |
| **Symbols Nerd Font** | Icons-only font behind the prompt, `eza --icons` and powerline separators, and the fallback when MonoLisa is absent. |

### Shell framework

`bootstrap.sh` clones these at fixed commits, because Oh My Zsh publishes no tags and a
floating checkout would make two machines differ for no reason:

| Component | Role |
|---|---|
| **Oh My Zsh** | Loads plugins and themes; its `git` plugin supplies the aliases the shell assumes. |
| **powerlevel10k** | The prompt: two lines, instant prompt, git status, and the glyph segments configured in `.p10k.zsh`. |

### Plugins fetched after the configs land

| Plugin | Role |
|---|---|
| **tpm** | tmux plugin manager; cloned to `~/.tmux/plugins/tpm` and run from `.tmux.conf`. |
| **tmux-sensible** | Baseline tmux settings that are safe to agree with. |
| **tmux-resurrect** | Saves and restores sessions across restarts. |
| **tmux-cpu** | CPU load segment in the status bar, pinned to a commit because upstream has no tags. |
| **tmux-battery** | Battery segment in the status bar. |
| **catppuccin/tmux** | Status bar theme, fixed to Macchiato. |
| **yazi: what-size** | Shows real directory sizes on demand, bound to `M` and `C`. |
| **yazi: my-commands** | Personal command menu bound to `F2`; vendored in this repo because it has no upstream. |
| **yazi flavors** | `catppuccin-macchiato` (active), `catppuccin-mocha`, `dracula` and `ayu-dark`, switchable in `theme.toml`. |

### Settings written into `$HOME`

| Target | What it sets |
|---|---|
| `.zshrc` | Oh My Zsh with powerlevel10k, `PATH` deduplication, `eza`/`bat`/`lazygit` aliases, word-wise `Ctrl+Arrow` bindings, and the `y` wrapper that makes yazi change directory. |
| `.zprofile` | Homebrew shellenv and nvm for login shells. |
| `.zshenv` | Cargo environment for every zsh process. |
| `.profile`, `.tcshrc` | Docker and Cargo paths for the legacy shells. |
| `.p10k.zsh` | Prompt layout: instant prompt, two-line prompt, icons and segments. |
| `.tmux.conf` | `tmux-256color`, true colour and clipboard for `xterm-ghostty`, mouse on, the six pinned plugins, Macchiato status bar. |
| `.wezterm.lua` + `.wezterm-themes/` | WezTerm fallback: MesloLGS NF at 14pt, no tab bar, Catppuccin Macchiato. |
| `.config/ghostty/config` | Theme, font stack, window padding, Option-as-char, German-safe tab and split keys, quick terminal, notification policy. |
| `.config/btop/` | btop settings plus the Catppuccin Macchiato theme file it references. |
| `.config/yazi/` | File-manager layout, mime-based openers, preview tasks, Vim-style keymap, theme selection. |
| `.config/opencode/` | `cli.json` for theme, diff wrapping and session UI; `opencode.jsonc` as the global config stub. |
| `.gitconfig` | Commit identity, delta pager, `diff3` merge conflicts, coloured moved lines, no signing, no editor. |
| `.agents/` | 27 pinned agent skills plus `.skill-lock.json`, which records each upstream and content hash. |

### Deliberately not installed

Four things are left out on purpose. The first two cannot be redistributed; the last two are
developer toolchains that a given machine may not need.

| Not installed | Why |
|---|---|
| **MonoLisa** | Commercial, not redistributable. Install your own licensed copy — see `docs/fonts.md`. |
| **MesloLGS NF** | Only used by the WezTerm fallback; install it if you use WezTerm. |
| **Rust, nvm, Docker, Herd** | Guarded in the shell configs: absent means a warning from `verify.sh`, never an error. |
| **`Brewfile.optional`** | A snapshot of every other app on this machine. Install with `brew bundle install --file=Brewfile.optional` if you want all of it. |

## Verifying

```sh
./scripts/verify.sh            # the applied machine: apps, pty, tmux, fonts
./scripts/verify.sh --static   # repo-side only: manifest, dependencies, pins
./scripts/check-bare-shell.sh  # simulated bare Mac: no Rust, nvm, Docker, Herd
```

`verify.sh` prints one row per check, `pass` / `warn` / `FAIL`, and exits non-zero only on
failure. It asserts behaviour, not file contents: the Ghostty config parses, text and icon
faces resolve, zsh loads cleanly through a pty, tmux starts with every plugin at its pinned
ref, and the required tools are actually on `PATH`. Missing requirements fail; absent
optional toolchains and the licensed font warn. Two checks are about the repo rather than the
machine: one fails if a font binary becomes tracked, the other if a managed config contains
something secret-shaped.

`--static` skips everything that needs Ghostty, a pty or a tmux server, which makes it the
mode to run on a machine that has just finished bootstrapping.

`check-bare-shell.sh` builds a throwaway `$HOME` with only the managed zsh files and the
pinned framework, starts an interactive zsh with the optional toolchains absent, and fails if
any error reaches the terminal. It is the proof that the shell degrades instead of breaking;
`--rev <commit>` runs the same test against an older revision.

## What stays manual after bootstrap

1. **Default terminal app.** macOS has no dependable CLI for this. Set Ghostty as the default
   in System Settings (or via Finder's "Open With"). iTerm2 and WezTerm stay installed as
   fallbacks.
2. **MonoLisa, if missing.** Licensed software, so it is not distributed here and has no
   Homebrew formula. `verify.sh` reports a warning and the terminals fall back through the
   font chain. See `docs/fonts.md`.
3. **MesloLGS NF, if you use WezTerm.** Same situation: installed by hand, not managed.

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
scripts/check-bare-shell.sh  simulated bare Mac: the shell must start clean
GLOSSARY.md             terms: bare Mac, applied machine, required vs optional
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
- **A bare Mac is the success criterion.** Required versus optional is a deliberate split, not
  an accident of what happens to be installed: see
  [`docs/adr/0003-bare-mac-as-the-goal.md`](docs/adr/0003-bare-mac-as-the-goal.md).
- **Option stays a character key** on the German layout (`macos-option-as-alt = false`).
  Option types `@ { } [ ] | \ ~ €`; word movement lives on `Ctrl+Left/Right` and
  `Ctrl+Backspace`, bound in `.zshrc`.
- **The theme is fixed Macchiato, not system-following.** tmux cannot observe the macOS
  appearance switch, so the status bar stays Macchiato; `window-theme = dark` keeps the frame
  matching. See [`docs/themes.md`](docs/themes.md) for switching.
- **tmux is for persistence, not splitting.** Long-running work in named sessions; quick
  side-by-side work in Ghostty's native splits. Scrollback is capped at 10,000 lines and
  window restore is off because tmux owns persistence.
- **MonoLisa ships as a variable pair** (no separate Bold), so bold is synthesized. The escape
  hatch is putting `MesloLGS NF` ahead of it in the Ghostty font list.
- **`tmux-cpu` is pinned to a commit, not a tag** — the only plugin whose upstream publishes
  no tags (`#bcb110d`).
- **`core.editor` is deliberately unset.** Interactive committing goes through `lazygit`.

## Licence

MIT — see [`LICENSE`](LICENSE). Third-party material keeps its own terms: the vendored agent
skills, Catppuccin themes and Tabler icons are MIT with attribution collected in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). MonoLisa is commercial and is **not**
included; see [`docs/fonts.md`](docs/fonts.md).
