# chezmoi for dotfiles, with age as the encryption backend

Status: accepted

This repository is both the dotfiles source of truth and the chezmoi source directory, so
`chezmoi apply` reads the working tree directly and there is no second copy under
`~/.local/share/chezmoi`. We picked chezmoi over GNU Stow or a hand-rolled symlink script
because the scope is a full dotfiles takeover across future machines: chezmoi gives
idempotent apply, `diff` before `apply`, per-machine templates, and built-in encryption
without us maintaining that machinery. age was chosen over GPG because GPG in this setup
already means signing keys and pinentry, and a dotfiles secret should not depend on the
same keyring.

Consequences worth knowing:

- **Encryption is configured but unused.** An age recipient exists; no file is encrypted.
  Everything credential-shaped (GPG keys, `gh` auth, codex/opencode auth) stays out of the
  repository by decision, so there is nothing to encrypt yet. The first secret is
  `chezmoi add --encrypt`.
- **MonoLisa was committed in plaintext** while the repository was private, so the font
  reached a new machine without a key handoff. That is no longer possible: the font is
  commercial and not redistributable, so it stopped being managed here when the repository
  was published. See [ADR 0002](0002-publishing-the-repository.md) and `docs/fonts.md`.
- **The age private key is not in the repository.** If encryption is ever used, the key has
  to be backed up outside the repo (password manager), or a fresh machine cannot decrypt.

## Considered options

- **GNU Stow** — legible layout, well understood, but no per-machine variation and no
  secrets story. Ceiling reached the first time two Macs need different values in one file.
- **Hand-rolled `install.sh` + symlinks** — no dependency, but we would own backup handling,
  idempotency, drift detection and per-machine branching forever.
- **yadm** — tracks files in place without copying, but the encryption and templating
  ergonomics are weaker and it adds a git wrapper on top of git.
- **GPG instead of age** — rejected to keep dotfile secrets off the signing keyring.
