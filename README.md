# dotfiles

Personal macOS dotfiles, managed by [chezmoi](https://www.chezmoi.io/). Terminal-first:
Ghostty, zsh with powerlevel10k, tmux.

This repository **is** the chezmoi source directory. There is no second copy under
`~/.local/share/chezmoi` — `chezmoi apply` reads the working tree.

## New machine

```sh
git clone git@github.com:footstep27/dotfiles.git ~/Repositories/dotfiles
cd ~/Repositories/dotfiles
./bootstrap.sh --dry-run     # see the plan
./bootstrap.sh
```

`bootstrap.sh` is idempotent and does, in order: Homebrew (installing it if absent) →
required packages from `Brewfile` → chezmoi source wiring (including the age recipient) →
archive of the managed dotfiles when any of them drifted → `chezmoi apply` → Ghostty
terminfo → tmux plugins at their pinned refs → `scripts/verify.sh`.

## Daily use

```sh
chezmoi diff        # what would change in $HOME
chezmoi apply       # make $HOME match the repo
chezmoi edit FILE   # edit the repo copy, then apply
chezmoi update      # pull from GitHub and apply in one step
```

Look at `diff` before `apply`. The first bootstrap archives what it overwrites to
`~/.dotfiles-backup-<timestamp>/dotfiles.tar.gz`; later runs only archive when your local
files have drifted from the repo.

## Verifying

```sh
./scripts/verify.sh
```

One row per check, `pass` / `warn` / `FAIL`; exit status is non-zero only when something
failed. It asserts behaviour — the Ghostty config parses, the text and icon faces actually
resolve, zsh loads cleanly through a pty, tmux starts with every plugin at its pinned ref,
the Brewfile is satisfied — not the contents of config files.

## What this repo owns

| Area | Managed |
|---|---|
| Shell | `.zshrc`, `.zprofile`, `.zshenv`, `.p10k.zsh`, legacy `.tcshrc` and `.profile` |
| Ghostty | `~/.config/ghostty/config` |
| tmux | `.tmux.conf` (plugins pinned here, installed via TPM) |
| WezTerm | `.wezterm.lua` + the one theme file actually used |
| TUIs | `yazi` config only |
| Fonts | the licensed MonoLisa pair (see `docs/fonts.md`) |
| Git | global `.gitconfig` |
| Packages | `Brewfile` (required), `Brewfile.optional` (snapshot, installed on request) |

Deliberately **not** managed: credentials (GPG keys, `gh`, codex/opencode auth), opencode's
own config directory (it self-manages, including a plugin tree with `node_modules`), nvim
config, shell histories, Oh My Zsh (Homebrew-vendored), tmux plugin trees, the WezTerm
theme repository clone, `yazi` flavors/plugins.

Two entries in the original plan are empty on this machine and therefore unmanaged:
`~/.vim` contains only netrw's history file, and `~/.config/btop` is an empty `themes/`
directory with no `btop.conf`. Managing them would track noise. If either gets real config
later, `chezmoi add` it.

## Two steps that stay manual

1. **Default terminal app.** macOS has no dependable CLI for this. Set Ghostty as the
   default in System Settings (or via Finder's "Open With"). iTerm2 and WezTerm are left
   installed as fallbacks.
2. **MonoLisa, if missing.** It is licensed software and cannot be installed by Homebrew.
   `verify.sh` reports a *warning*, not a failure, and the terminal still works through the
   fallback chain. See `docs/fonts.md`.

## Decisions worth knowing

- **The repo is the chezmoi source,** and age is the chosen encryption backend. Reasoning,
  including why encryption is currently unused, is in
  [`docs/adr/0001-chezmoi-and-age.md`](docs/adr/0001-chezmoi-and-age.md).
- **Option stays a character key** on the German layout (`macos-option-as-alt = false`).
  Option types `@ { } [ ] | \ ~ €`; word movement lives on `Ctrl+Left/Right` and
  `Ctrl+Backspace`, bound explicitly in `.zshrc`.
- **tmux is for persistence, not for splitting.** Long-running work in named sessions;
  trivial side-by-side work in Ghostty's native splits. The status bar stays Catppuccin
  Mocha because tmux cannot observe the macOS appearance switch.
- **Scrollback is capped at 10,000 lines** and window state restore is off, because tmux
  owns persistence.
- **MonoLisa ships as a variable pair** (no separate Bold), so bold is synthesized. The
  escape hatch is putting `MesloLGS NF` ahead of it in the Ghostty font list.
- **No hollow unfocused cursor.** Ghostty 1.4 has no such setting; the cursor is a block and
  does not blink, with `unfocused-split-opacity` marking inactive splits instead.
- **`tmux-cpu` is pinned to a commit, not a tag.** It is the only plugin whose upstream
  publishes no tags, so the pin is `#bcb110d`.
- **age is wired but idle.** `bootstrap.sh` generates an identity at
  `~/.config/chezmoi/key.txt` and records the recipient; no file is encrypted. Back that key
  up somewhere real (password manager) before the first secret depends on it — a new machine
  cannot decrypt without it.
- **`core.editor` is deliberately unset.** Interactive committing goes through `lazygit`.

## Layout

```
bootstrap.sh            fresh-machine entry point (--dry-run supported)
scripts/verify.sh       health checks for the applied machine
Brewfile                required packages
Brewfile.optional       snapshot of the rest of the inventory
dot_* / dot_config/     chezmoi-managed configs (names map to $HOME)
dot_tmux.conf           tmux, including pinned plugin refs
docs/                   fonts, decisions
```

Adding a config: put it where it lives in `$HOME` via `chezmoi add <path>`, then commit.
Anything repo-only (docs, scripts, manifests) must be listed in `.chezmoiignore`, otherwise
chezmoi will try to copy it into your home directory.
