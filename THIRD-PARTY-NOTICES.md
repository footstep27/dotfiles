# Third-party notices

This repository redistributes some third-party material and installs other material directly
from its upstream. Each item remains under its own licence; the MIT text below is reproduced
verbatim as the licence requires. The repository's own MIT licence in `LICENSE` does not
extend to any of it.

Skill repositories are not redistributed: `bootstrap.sh` clones them at setup
time, so they remain under their own licences at their own upstreams.

## Agent skills — installed from upstream, not vendored

`scripts/skills.conf` names the upstreams; `bootstrap.sh` clones them and links
the skills into `~/.agents/skills`. No skill content lives in this repository.

| Upstream | What is installed | Licence |
|---|---|---|
| https://github.com/mattpocock/skills | every skill under `skills/engineering` and `skills/productivity` | MIT, Copyright (c) 2026 Matt Pocock |
| https://github.com/cathrynlavery/diagram-design | `diagram-design` | MIT, Copyright (c) 2025 Cathryn Lavery |
| https://github.com/vercel-labs/skills | `find-skills` | MIT, Copyright (c) 2026 Vercel, Inc. |

## Catppuccin

- `dot_wezterm-themes/catppuccin-macchiato.toml` — from
  https://github.com/catppuccin/wezterm
- `dot_config/btop/themes/catppuccin_macchiato.theme` — from
  https://github.com/catppuccin/btop

MIT, Copyright (c) 2021 Catppuccin.

## Not included

MonoLisa is commercial and is **not** distributed here. See `docs/fonts.md` for
the font that is used instead.

## Installed but not redistributed

**Maple Mono NF** is pulled from Homebrew (`font-maple-mono-nf`); no font binary
is committed to this repository. Upstream:
https://github.com/subframe7536/maple-font — SIL Open Font License 1.1,
Copyright (c) 2022 subframe7536. Its credits list JetBrains Mono, Roboto Mono,
Fira Code, Victor Mono, Commit Mono, Recursive and MonoLisa as influences; each
keeps its own licence.

---

## MIT License — Catppuccin

```
MIT License

Copyright (c) 2021 Catppuccin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
