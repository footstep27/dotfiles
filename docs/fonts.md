# Fonts

## MonoLisa

`Library/Fonts/MonoLisaNormal.ttf` and `Library/Fonts/MonoLisaItalic.ttf` are managed here
and committed to this **private** repository, taken from the purchased originals and
hash-verified against them.

MonoLisa is commercial, licensed software. It is:

- **not** redistributable — do not publish this repository, make it public, or add
  collaborators without removing these files first;
- **not** installable via Homebrew, and deliberately absent from both Brewfiles;
- shipped as a **variable** pair (`Normal`, `Italic`) rather than separate weight files.

### Consequence for bold text

There is no `MonoLisaBold.ttf`, so terminals that cannot drive a variable font's weight
axis synthesize bold. At 14pt this is acceptable. If it ever reads badly, the escape hatch
is to put `MesloLGS NF` ahead of MonoLisa in the Ghostty font list — icons keep working
either way because the symbols-only Nerd Font is the declared fallback.

### Missing font on a new machine

A machine without MonoLisa still works: the fallback chain resolves to the symbols font and
`scripts/verify.sh` reports a **warning**, never a failure. To fix it, copy the two files
from the licensed source into `~/Library/Fonts` and run `chezmoi apply`.

## Symbols Nerd Font

Installed from the required Brewfile (`font-symbols-only-nerd-font`). Icons only — no
letters — so it can never accidentally win over MonoLisa for text.

## MesloLGS NF

Not managed here. It is the face the existing powerlevel10k configuration was tuned
against and was already installed; the symbol fallback makes it unnecessary unless MonoLisa
is missing.
