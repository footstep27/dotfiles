# Agent skills are floating upstream checkouts

Status: accepted

Vendored copies in `dot_agents/skills/` went stale the moment they were committed. Updating
them meant running an external installer, `chezmoi re-add ~/.agents`, reviewing a 27-skill
diff and pushing; in practice the repository kept a snapshot that already lacked new upstream
skills. The copies also duplicated content that upstream owns and invites people to edit.

`bootstrap.sh` now reads `scripts/skills.conf`, shallow-clones each upstream under
`~/.local/share/dotfiles/upstreams/<owner>/<repo>`, and symlinks every skill directory into
`~/.agents/skills`. Re-running bootstrap fast-forwards each checkout to the upstream default
branch and prints the resulting SHA. OpenCode's skill scanner resolves symlinked directories,
so the links are transparent to the agent. The repository keeps the manifest and the logic,
not the skills.

Floating is a deliberate exception to this repo's pin-everything posture. Oh My Zsh,
powerlevel10k, tmux plugins and yazi packages are pinned because an unexpected change there
can break the terminal between runs. Skills are prose and references read by an agent, they
change often, and upstream's own guidance is to keep them current. A dirty checkout is left
alone and reported: local edits win, because upstream explicitly invites hacking on the files.

## Consequences

- `dot_agents/` and `.opencode/skills/diagram-design/` are gone. `scripts/skills.conf` is the
  single list of what installs, and `scripts/lib-skills.sh` is the only code that touches it.
- `~/.agents/skills` holds symlinks, not managed files. `.chezmoiignore` guards the links,
  the checkouts and the migration backup so `chezmoi add --recursive` cannot pull them in.
- The first run after this change backs up existing real directories and foreign symlinks at
  tracked skill names, plus `~/.agents/.skill-lock.json`, under
  `~/.agents/skills.pre-checkout-<timestamp>/`, then links the tracked set.
- Network failures, duplicate skill names and stale links warn; bootstrap still finishes and
  `verify.sh` reports the gap. A fresh machine offline is still a usable terminal.
- `diagram-design` is global rather than project-scoped, so the README export command reads
  from `~/.agents/skills/diagram-design/`.

## Considered options

- **Keep vendoring and update on a schedule.** Reproducible and offline-friendly, but it is a
  second source of truth that needs a manual re-add plus a commit for every upstream change.
- **Use `npx skills add` in bootstrap.** Matches upstream's instructions, but adds Node and an
  installer as a bootstrap dependency, copies by default, and writes a lockfile this repo
  would then have to manage.
- **Git submodules in this repository.** Pins content without vendoring, but updating is still
  an explicit commit, the checkout lives inside the repo, and agents would follow a path that
  changes with every clone.
- **Copy the skills into `~/.agents/skills`.** Simpler lookup, but every update rewrites the
  copies and local edits are lost. Symlinks keep one canonical copy per upstream.
