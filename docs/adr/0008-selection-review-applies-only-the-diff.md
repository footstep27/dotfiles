# Reviewing the selection applies only the diff

Status: accepted

`bootstrap.sh --select` used to save the whole selection and then run the complete bootstrap:
required packages, every selected optional package, `chezmoi apply`, macOS groups, skills,
the shell framework, tmux and yazi. Reviewing one checkbox re-ran everything. Deselecting a
package or config only changed what future runs would install; the package stayed installed
and the live config stayed on disk until a separate `--prune`.

`--select` now compares the saved selection with the reviewed one and applies only the
difference:

- newly selected packages are installed from a temporary Brewfile containing just those items
  and their taps;
- newly selected configs are applied from their target paths;
- newly selected macOS groups are applied;
- newly deselected optional packages are uninstalled;
- newly deselected configs are pruned;
- deselected macOS groups are left in place, because their values are not files and
  `--revert-macos` is the explicit undo;
- required packages, skills, the shell framework, tmux, yazi and verification are skipped.

The delta path exits after applying. A plain `./bootstrap.sh` still runs the full idempotent
setup. `--select` needs `chezmoi`; on a machine that has not been bootstrapped it warns and
falls back to the full run, so the first checklist still works.

Uninstalling is deliberately part of the review. The checklist is the confirmation, every
removal is printed, and a backup of managed files is taken before configs are applied or
pruned. Homebrew removals never use `--zap`; casks keep their user data.

## Consequences

- Deselecting an optional package is destructive. This supersedes the “deselection never
  uninstalls” consequence in ADR 0005.
- Deselecting a config removes its live files immediately. `--prune` remains for configs left
  stale by an older selection.
- `--select` no longer repairs an unrelated drift. Run `./bootstrap.sh` for the full pipeline
  and `./scripts/verify.sh` for the full check.
- Package removals can fail when another installed formula depends on the removed one; the
  script warns and continues.
- A bare machine falls back to the full bootstrap, where deselected packages are not removed
  because there is no previous selection to diff against.

## Considered options

- **Save and exit.** Safest, but it does not answer “apply my selection changes”; the user
  would have to run a second command.
- **Keep the full bootstrap and add pruning on deselection.** Smaller change, but reviewing one
  selection still reinstalls and re-applies everything.
- **A separate `--apply-selection` flag.** Keeps review and apply separate, but adds a second
  command and a second place to forget.
- **Use `brew bundle cleanup`.** It would remove everything not in the generated Brewfile,
  including unrelated user-installed packages, so it is too broad.
