# macOS preferences are inventory groups, not managed files

Status: accepted

macOS preferences are per-user property-list values, not files under `$HOME` that chezmoi
owns. A `run_onchange` script would execute on every machine, with no per-machine opt-out and
no read-back, and rewriting a whole preference domain would clobber keys the repository does
not understand.

The repository now has four optional groups — `macos:keyboard`, `macos:finder`,
`macos:screenshots` and `macos:apps` — declared in `scripts/macos-defaults.tsv`. They use a
separate `macos` inventory kind, start unchecked, and are applied after `chezmoi apply` only
when selected. The manifest is the single source of truth for apply, verification and revert.

Writes are deliberate: bootstrap reads the current value, normalises booleans and numbers,
skips keys that already match, and records the previous value before the first change.
`--revert-macos` restores those values, restarts the affected UI owner, and exits without
running the rest of bootstrap. Deselecting a group stops future application but does not undo
it, matching the rule that deselection never uninstalls.

Verification warns instead of failing. These are preferences, not required infrastructure; an
OS update or a visit to System Settings should be visible without turning the machine red.
Finder, Dock and SystemUIServer are relaunched only when one of their keys changed. User apps
are left alone and told to relaunch.

The manifest excludes settings that need `sudo`, change the security posture, or depend on
optional hardware. Touch ID for `sudo`, the firewall, Gatekeeper and FileVault stay manual.

## Consequences

- A new `macos` item kind joins `brew`, `cask`, `config`, `npm`, `vscode` and `tap`. It is not
  written into the generated Brewfile and carries no managed paths.
- `~/.local/state/dotfiles/macos-defaults.before` is machine state: one line per key changed,
  with `__unset__` when there was no previous value. Revert deletes the file when every value
  was restored.
- `verify.sh --static` reads selected groups back and warns with the offending keys.
- Adding a preference means adding a manifest row, not editing shell branches.
- The before-file is intentionally not a full domain export: it records only the keys the
  repository touched, so revert cannot overwrite unrelated settings.

## Considered options

- **A chezmoi `run_onchange` script.** No bootstrap code, but it runs for everyone, cannot be
  toggled per machine, and has no typed read-back or revert.
- **An always-on bootstrap step.** Fewer moving parts, but a work machine cannot opt out and
  every new preference becomes mandatory.
- **Reuse the `config` kind with empty paths.** Less code, but `config` means “managed file
  group”, those toggles default on, and `--prune` would have nothing sensible to do.
- **Manage the plist files directly.** Makes chezmoi the owner of whole domains and risks
  overwriting unrelated keys or fighting `cfprefsd`.
- **Export whole domains before applying.** Complete, but restore would replay unrelated
  settings and the exports are much larger than the handful of keys actually changed.
