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

**Managed file**:
A file in this repository that chezmoi copies into `$HOME`.
_Avoid_: dotfile

**Repo-only file**:
A file tracked here that chezmoi ignores — the README, `docs/`, `scripts/`, the manifests.
_Avoid_: untracked file
