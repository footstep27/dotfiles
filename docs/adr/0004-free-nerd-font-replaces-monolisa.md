# A free Nerd Font replaces MonoLisa

Status: accepted

MonoLisa could not stay: it is commercial and not redistributable, so it was
removed from a now-public repository and became a manual install. It also left a
second problem — it carries no Nerd Font glyphs, so the setup needed a patched
symbols font beside it, meaning the terminal looked wrong until **two** fonts
were installed by hand.

Maple Mono NF removes both problems. It is SIL OFL 1.1, so the Homebrew cask can
be declared in the Brewfile and reproduced by `bootstrap.sh`; and it ships the
Nerd Font icon set in the text face, so the fallback disappears. Its metrics are
the same as MonoLisa's (0.55 em x-height, 0.6 em cell), which is why the
replacement does not reflow the terminal.

## Consequences

- Nothing about fonts is manual any more. `docs/fonts.md` documents a choice,
  not a procedure, and `verify.sh` fails rather than warns when the face is
  missing — a required package now, not a licensed extra.
- `font-symbols-only-nerd-font` and `MesloLGS NF` are no longer part of the
  setup; the WezTerm fallback uses Maple Mono NF too.
- The licensed-font guard in `.gitignore` and `verify.sh` stays, because the
  cheap way to break this repository is still to commit a font binary.

## Considered options

- **Keep MonoLisa as a manual install.** Preserves the exact look, but the
  bare-Mac requirement cannot be met by a font nobody may redistribute, and two
  manual font steps resist the whole point of the repository.
- **JetBrains Mono NF or Monaspace NF.** Both are credible and single-cask; they
  were rejected only on likeness, not quality. Switching later is a `font-family`
  line plus one cask.
- **Patch MonoLisa for Nerd Font glyphs.** The EULA forbids modifying glyphs or
  making derivative works, and a patched copy could not be committed anyway.
