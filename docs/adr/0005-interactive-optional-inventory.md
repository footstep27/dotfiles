# Optional inventory is a per-machine selection, not presets

Status: accepted

A single `Brewfile.optional` snapshot forced every machine to choose between "none of it" and
"all of it", which does not survive the private/work split: Steam belongs on one machine and
not the other. `bootstrap.sh` now opens a dependency-free checklist built from categorized
manifests in `Brewfile.d/`, saves the checked items to
`~/.local/state/dotfiles/selection`, and materializes the chosen subset into a generated
Brewfile. The required `Brewfile` stays non-negotiable; only the optional inventory is a
selection.

Named profiles were rejected: two presets become a third thing to maintain, and the real
difference between machines is a handful of individual apps, not a persona. The menu is one
screen with categories and individual toggles, so "private" and "work" are simply different
saved selections. Package configs travel with their package where a binding exists (WezTerm);
configs for required tools are separate toggles, which keeps "install" and "configure"
separable without weakening the required baseline.

## Consequences

- `Brewfile.optional` is gone; `Brewfile.d/*.txt` is the inventory and `--all-optional`
  replaces the old "install the snapshot" instruction.
- `.chezmoiignore` is a template that reads a generated ignore list, so unchecking a config
  really prevents `chezmoi apply` from writing it.
- `verify.sh` judges the machine against its own selection: selected optional packages and
  configs must be present, deselected ones are ignored, and stale configs warn until
  `--prune` is passed.
- The selection is machine state, never repository content. It lives under
  `~/.local/state/dotfiles/` and is excluded from chezmoi.

## Considered options

- **Named profiles (`--profile work` / `--profile private`).** Easy first run, but a second
  source of truth: changing one app means editing a preset, and the preset hides what is
  actually installed.
- **Keep one flat `Brewfile.optional` and select from it.** No restructuring, but the file is
  an unsorted snapshot with duplicate required entries, and it has no place to declare
  config bindings, dependencies, or conflicts.
- **Uninstall deselected packages.** Tempting for symmetry, but destructive during a config
  apply; removal stays an explicit separate action.
