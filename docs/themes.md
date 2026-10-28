# Themes

## btop — Catppuccin Mocha

`~/.config/btop/themes/catppuccin_mocha.theme` is vendored from
[catppuccin/btop](https://github.com/catppuccin/btop) (`themes/catppuccin_mocha.theme`),
which is MIT licensed — Copyright (c) 2021 Catppuccin org.

It is copied into the repo instead of downloaded during bootstrap: it is 2.3 KB, works
offline, cannot drift from upstream, and has no runtime network dependency.

Compatibility notes:

- The file defines all 42 `theme[...]` keys that btop 1.4.8 expects, so nothing silently
  falls back to the built-in theme.
- Its `main_bg` is `#1e1e2e`, identical to the Ghostty Mocha background, so btop matches the
  terminal exactly.
- `theme_background = false` in `btop.conf` lets Ghostty's opacity and blur show through
  rather than painting an opaque block. There is no visual loss, since the theme background
  and the terminal background are the same colour.

`catppuccin_latte.theme` is deliberately not vendored: the terminal is fixed to Mocha, so a
light btop would be the only light surface on screen.

## Keeping btop in sync

btop rewrites `btop.conf` when you change settings in-app and confirm saving them. That makes
the file diverge from the repo, which `chezmoi diff` shows and `scripts/verify.sh` reports as
drift. If you change something deliberately, pull it back in:

```sh
chezmoi add ~/.config/btop/btop.conf
```
