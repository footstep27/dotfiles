# Fonts

## MonoLisa

`MonoLisaNormal.ttf` and `MonoLisaItalic.ttf` live in `~/Library/Fonts` and are **not**
managed by this repository. MonoLisa is commercial, licensed software from FaceType and is
not redistributable, so the files cannot be committed or published with the configs.

What that means in practice:

- a fresh machine has no MonoLisa until you install your own licensed copy;
- it is **not** installable via Homebrew and is deliberately absent from both Brewfiles;
- `scripts/verify.sh` reports a **warning**, never a failure, when it is missing — the
  terminal falls back through the font chain and stays usable;
- `scripts/verify.sh` **fails** if a font binary ever becomes tracked again.

### Installing your licensed copy

Buy MonoLisa from [monolisa.dev](https://www.monolisa.dev/), copy `MonoLisaNormal.ttf` and
`MonoLisaItalic.ttf` into `~/Library/Fonts`, and restart Ghostty. There is nothing to apply:
chezmoi does not own these files.

### Consequence for bold text

There is no `MonoLisaBold.ttf`, so terminals that cannot drive a variable font's weight
axis synthesize bold. At 14pt this is acceptable. If it ever reads badly, the escape hatch
is to put `MesloLGS NF` ahead of MonoLisa in the Ghostty font list — icons keep working
either way because the symbols-only Nerd Font is the declared fallback.

## Symbols Nerd Font

Installed from the required Brewfile (`font-symbols-only-nerd-font`). Icons only — no
letters — so it can never accidentally win over MonoLisa for text.

## MesloLGS NF

Not managed here. It is the face the existing powerlevel10k configuration was tuned
against and was already installed; the symbol fallback makes it unnecessary unless MonoLisa
is missing.
