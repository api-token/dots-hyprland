# Agent guide

This repo is end-4's **illogical-impulse** Hyprland dotfiles: a Bash installer (`setup`, `sdata/`), a Lua Hyprland config (`dots/.config/hypr/`), and a large Quickshell/QML desktop shell (`dots/.config/quickshell/ii/`).

**Before working, read [`docs/README.md`](docs/README.md).** It maps the project, tells you which doc in `docs/` covers your task, and lists known gotchas. Read the relevant doc instead of exploring the whole codebase.

## Rules

- When you change behavior that a doc in `docs/` describes, update that doc in the same commit.
- Docs cite `path:line`. Line numbers drift, so re-read the code before editing.
- User customizations belong in `~/.config/hypr/custom/*.lua` and `~/.config/illogical-impulse/config.json`, not in the defaults.
- Don't run `./setup` or `./diagnose` unless asked: they modify the host.
- Commit messages: use a short area prefix (`hypr: …`, `qs: …`, `gentoo: …`).
