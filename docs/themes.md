# Themes

The stack is fixed to Catppuccin Macchiato, dark, on every surface:

| Surface | Theme |
|---|---|
| Ghostty | `Catppuccin Macchiato` (built-in) |
| tmux | `catppuccin/tmux` with `@catppuccin_flavor "macchiato"` |
| yazi | `yazi-rs/flavors:catppuccin-macchiato` |
| btop | vendored `catppuccin_macchiato.theme` |
| WezTerm | vendored `catppuccin-macchiato.toml` |

## btop — Catppuccin Macchiato

`~/.config/btop/themes/catppuccin_macchiato.theme` is vendored from
[catppuccin/btop](https://github.com/catppuccin/btop) (`themes/catppuccin_macchiato.theme`),
which is MIT licensed — Copyright (c) 2021 Catppuccin org.

It is copied into the repo instead of downloaded during bootstrap: it is 2.3 KB, works
offline, cannot drift from upstream, and has no runtime network dependency.

Compatibility notes:

- The file defines all 42 `theme[...]` keys that btop 1.4.8 expects, so nothing silently
  falls back to the built-in theme.
- Its `main_bg` is `#24273a`, identical to the Ghostty Macchiato background, so btop matches
  the terminal exactly.
- `theme_background = false` in `btop.conf` lets the terminal background show through rather
  than painting a duplicate block. There is no visual loss, since the theme background and
  the terminal background are the same colour.

`catppuccin_latte.theme` is deliberately not vendored: the terminal is fixed to Macchiato, so
a light btop would be the only light surface on screen.

## Keeping btop in sync

btop rewrites `btop.conf` when you change settings in-app and confirm saving them. That makes
the file diverge from the repo, which `chezmoi diff` shows and `scripts/verify.sh` reports as
drift. If you change something deliberately, pull it back in:

```sh
chezmoi add ~/.config/btop/btop.conf
```
