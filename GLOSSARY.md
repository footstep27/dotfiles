# dotfiles

The chezmoi source that takes a bare Mac to a defined terminal setup, and the vocabulary used
to talk about that transition.

## Language

**Bare Mac**:
Stock macOS with an administrator account and network access, and nothing else — no Command
Line Tools, no Homebrew, no git, no shell customisation.
_Avoid_: fresh Mac, clean machine

**Applied machine**:
A machine where the managed files have been copied into `$HOME` and the required toolchain is
installed; the state `verify.sh` inspects.
_Avoid_: configured machine, installed setup

**Required dependency**:
A tool the terminal setup cannot work without; its absence is a verification failure.
_Avoid_: mandatory package, hard dependency

**Optional toolchain**:
A tool the shell detects and uses when present, and skips when absent; its absence is a
verification warning.
_Avoid_: soft dependency, nice-to-have

**Selection**:
The set of optional items checked for one machine and saved outside the repository; machines
differ only by their selection.
_Avoid_: profile, preset, machine type

**Optional category**:
One editable manifest under `Brewfile.d/` that groups optional items for display and maps them
to a generated Brewfile fragment.
_Avoid_: bundle, group, pack

**Required baseline**:
The entries in `Brewfile` that every machine installs; they appear as locked rows in the menu
and are never part of the selection.
_Avoid_: mandatory set, core package

**Config toggle**:
A managed-file group that can be applied independently of whether its tool is installed.
_Avoid_: config profile, optional file

**Managed file**:
A file in this repository that chezmoi copies into `$HOME`.
_Avoid_: dotfile

**Repo-only file**:
A file tracked here that chezmoi ignores — the README, `docs/`, `scripts/`, the manifests.
_Avoid_: untracked file

**Skill upstream**:
A git repository that publishes one or more agent skills.
_Avoid_: skill repo, plugin

**Skill checkout**:
The machine-local clone of a skill upstream, owned by bootstrap.
_Avoid_: cache, install dir

**Skill link**:
A symlink in `~/.agents/skills` that points at one skill directory inside a skill checkout.
_Avoid_: shortcut, mount

**Floating checkout**:
A checkout that bootstrap fast-forwards to its upstream default branch on every run.
_Avoid_: latest, auto-update

**Pinned checkout**:
A checkout held at a commit recorded in this repository; Oh My Zsh, powerlevel10k, the tmux plugins and the yazi packages are pinned.
_Avoid_: locked checkout, fixed version
