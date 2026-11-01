# Fonts

## Maple Mono NF

One font does the whole job here. `Maple Mono NF` supplies the text face and the
Nerd Font glyph set in the same family, so the prompt, `eza --icons`, and the
tmux status segments all resolve without a symbols fallback.

- Installed by the required Brewfile: `brew install --cask font-maple-mono-nf`.
- Free under the SIL Open Font License 1.1, so it can be declared here and
  reproduced on any machine. No manual step, no licence to buy.
- Its proportions match MonoLisa's — 0.55 em x-height, 0.6 em cell — which is
  why it is the replacement rather than a compromise.
- Ships real `Bold` and `Bold Italic` faces, so nothing is synthesised.

`scripts/verify.sh` asks Ghostty which face answers `a` and two Nerd Font
codepoints, and fails unless all three come back as Maple Mono NF.

## Why not MonoLisa

MonoLisa is commercial and not redistributable, so it could not live in a public
repository and was removed in [ADR 0002](adr/0002-publishing-the-repository.md).
It also needed a second font for icons, which made the setup depend on two things
that could not be installed by a manifest. See
[ADR 0004](adr/0004-free-nerd-font-replaces-monolisa.md) for the switch.

## Using a different font

Any Nerd Font works. Change `font-family` in `~/.config/ghostty/config` and swap
the cask in the `Brewfile`, then run `./scripts/verify.sh`. In a terminal, use
the plain `Nerd Font` variant (double-width icons), not `Nerd Font Mono`
(single-cell icons, for editors) or `Nerd Font Propo` (proportional).

JetBrains Mono NF and Monaspace NF are the closest substitutes at the same
proportions; both are single-command casks.

## Icons without a Nerd Font

Not supported on purpose. Without the patched glyphs the prompt draws boxes, and
the failure is loud in `verify.sh` rather than silent.
