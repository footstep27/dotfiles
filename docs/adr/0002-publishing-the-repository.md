# Publishing the repository

Status: accepted

The repository started private, and two decisions depended on that: the licensed MonoLisa
font files were committed in plaintext so a new machine could install them without a key
handoff, and the global `.gitconfig` carried a personal email address. Both are fine in a
private repo and become defects the moment anyone can clone it.

Publishing is worth the cleanup because the interesting part of this setup is the reasoning,
not the files: the ADRs, the pinned plugin refs and the `verify.sh` checks are cheaper to
share than to explain.

## Decision

Publish under MIT, and remove everything from history that would not be legal or sensible to
publish:

- **The font files leave the history entirely**, not just `HEAD`. Deleting a file in a later
  commit leaves the blob reachable at an earlier SHA in a public repo, which is exactly the
  redistribution the licence forbids. MonoLisa becomes a documented manual install.
- **The working notebook (`.scratch/`) leaves the history too.** It is process material and
  would otherwise be permanently browsable for no reader's benefit.
- **Commit metadata is rewritten to a GitHub `noreply` address.** Rewriting history was
  already required for the font, so scrubbing the address cost one more `--replace-text`
  rule. The `flowinho` display name stays: it is a public handle.
- **The GPG signing key id is dropped from `.gitconfig`.** Signing was already off and the
  key's UID is the old address, so the id only invited broken-signature questions.
- **GitHub secret scanning and push protection are enabled** before the flip, because the
  most likely future mistake is `chezmoi add --recursive` sweeping machine-local state into
  the source directory. `verify.sh` now also fails if a font binary is ever tracked.

## Consequences worth knowing

- **Every commit SHA changes.** Other machines holding a clone must re-clone rather than
  pull; the bundle `dotfiles-prepublic.bundle` written before the rewrite is the only copy of
  the old history, and it stays outside the repository.
- **Publication is a one-way door.** A clone or a crawler can take the repository within
  minutes, so the visibility flip happens last, after a fresh-clone audit of what is
  reachable. Rolling back the setting does not recall what was copied.
- **A fresh machine needs a licensed MonoLisa copy** before the terminal looks as intended.
  This is a warning in `verify.sh`, not a failure, and the fallback chain keeps the machine
  usable.
- **`verify.sh` is not CI.** GitHub runs nothing on push; the checks assume an applied
  machine. Secret scanning, which *is* automated, is the one guard that lives server-side.

## Considered options

- **Stay private.** Costs nothing today and gives up the point of writing the docs down;
  rejected deliberately, not by accident.
- **Publish a fresh single commit.** Cleanest possible history, but loses 24 commit messages
  that record *why* the setup looks like this, which is the part worth sharing.
- **Strip the fonts from `HEAD` only.** The cheapest change, and the one that quietly
  redistributes the font through the commit graph.
- **Keep the personal address and rely on spam filtering.** Rejected: an address in public
  commit metadata is permanent and indexed within days, and the rewrite was happening anyway.
