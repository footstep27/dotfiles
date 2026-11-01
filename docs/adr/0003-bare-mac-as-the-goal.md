# A bare Mac is the success criterion

Status: accepted

This repository is published, but its purpose is not to be read: it exists so that a machine
with stock macOS, an admin user and a network connection becomes this setup in two manual
steps and one command. That definition now governs what belongs in the required manifest.

The split follows from it. A dependency is **required** when the terminal setup visibly breaks
without it — the shell framework, the shell plugins sourced by `.zshrc`, the terminal, the
multiplexer, the file manager, git tooling, and the agent CLI whose config is managed here.
Everything else is an **optional toolchain**: Rust, nvm, Docker and Herd are detected and
skipped, so their absence produces a warning from `verify.sh` rather than a shell that prints
errors before the prompt appears.

## Consequences

- `bootstrap.sh` installs Oh My Zsh and powerlevel10k itself, at fixed commits, because Oh My
  Zsh publishes no tags and Homebrew does not package it.
- Shell configs guard every optional block. A machine without Rust gets no `~/.cargo/env`
  error, and `scripts/check-bare-shell.sh` fails the build if that regresses.
- `verify.sh --static` is the check that runs on a freshly bootstrapped machine, before
  Ghostty or a tmux server exist.
- The two unavoidable manual steps are Command Line Tools (a GUI dialog) and the clone that
  makes `bootstrap.sh` reachable. Neither can be automated honestly.

## Considered options

- **Restore the full `Brewfile.optional` inventory as the goal.** Truer to "my machine", but
  a first run becomes an hours-long install that fails on one unavailable cask, and most of
  those apps have nothing to do with the terminal setup.
- **Treat every referenced tool as required.** Simpler to verify and wrong: it would force
  Rust, Node and Docker onto a machine that may only need a shell.
- **Leave the gaps documented instead of fixed.** That was the previous state: `verify.sh`
  was green while a genuinely bare Mac produced `no such file or directory: ~/.cargo/env` on
  the first line of every shell.
