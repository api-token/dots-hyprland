# Project docs (for agents)

Start here. These docs describe how **illogical-impulse** (end-4's Hyprland dotfiles) is put together, so you can make changes without reading the whole repo first. Each doc cites `path:line` so you can jump to the code. Treat a citation as a pointer and re-read the code before editing, because line numbers drift.

This checkout is a fork: `origin` = `api-token/dots-hyprland`, upstream = `end-4/dots-hyprland` (no `upstream` remote is configured).

## What the project is

| Part | Path | What it is |
|---|---|---|
| Installer | `setup`, `sdata/` | Bash dispatcher: per-distro deps, host setup, copies `dots/` into `$HOME`, maintenance subcommands |
| Diagnostics | `diagnose` | Writes a support report (`diagnose.result`) |
| Hyprland config | `dots/.config/hypr/` | **Lua** config (Hyprland ≥ 0.55): `hyprland.lua` loads the `hyprland/*` defaults, then the `custom/*` user overrides, then `shellOverrides` |
| Desktop shell | `dots/.config/quickshell/ii/` | Quickshell/QML shell (~74k lines, most of the project): bar, sidebars, overview, lock, AI chat, settings app… Two "panel families": `ii` (Material You, default) and `waffle` (Windows 11-like) |
| Other dotfiles | `dots/.config/*`, `dots/.local/` | matugen templates, kitty/foot, fish/zsh, starship, fuzzel, wlogout, Kvantum/KDE, fontconfig… |
| Extras | `dots-extra/` | Optional extras that are not installed by default |
| Repo meta | `.github/`, `licenses/` | README, CONTRIBUTING, issue/PR templates, moderation and notification workflows |

## Which doc to read

| Task | Read |
|---|---|
| Installer, `./setup` subcommands, how files get copied, uninstall, Python venv, `diagnose` | [setup-and-install.md](setup-and-install.md) |
| Adding or updating a package dependency (Arch / Fedora / Gentoo / Nix) | [distros.md](distros.md) |
| CI workflows, PR/issue conventions, `dots-extra/`, licenses, the submodule, commit-message style | [contributing-and-ci.md](contributing-and-ci.md) |
| Keybinds, window/layer rules, autostart, hypridle/hyprlock, where user overrides go | [hyprland.md](hyprland.md) |
| Wallpaper → Material You colors pipeline, matugen, terminals, GTK/Qt/KDE theming | [dotfiles-and-theming.md](dotfiles-and-theming.md) |
| Shell big picture: entry points, panel families, imports, **IPC/GlobalShortcut table**, translations, adding a panel, debugging | [quickshell/architecture.md](quickshell/architecture.md) |
| `Config.qml` (adding a config option), `Appearance`, `Directories`, `Persistent`, the widget library | [quickshell/config-and-common.md](quickshell/config-and-common.md) |
| System-integration singletons (audio, network, Hyprland data, notifications, AI, wallpapers, weather…) | [quickshell/services.md](quickshell/services.md) |
| Material panels: bar, sidebars, quick toggles, overview, OSD, lock, dock… | [quickshell/panels-ii.md](quickshell/panels-ii.md) |
| Windows 11-style panels: taskbar, start menu, action center… | [quickshell/panels-waffle.md](quickshell/panels-waffle.md) |
| Settings app pages; exposing a config option in the UI | [quickshell/settings-app.md](quickshell/settings-app.md) |

## Runtime locations (not in the repo)

| What | Where |
|---|---|
| Installed shell / Hyprland config | `~/.config/quickshell/ii/`, `~/.config/hypr/` |
| User shell config (`Config.options`) | `~/.config/illogical-impulse/config.json` |
| Persistent shell state | `~/.local/state/quickshell/states.json` |
| Generated colors | `~/.local/state/quickshell/user/generated/` (e.g. `colors.json`) |
| First-run marker | `~/.local/state/quickshell/user/first_run.txt` |
| Python venv | `$ILLOGICAL_IMPULSE_VIRTUAL_ENV` (default `~/.local/state/quickshell/.venv`) |

## How the pieces connect

- **Hyprland → shell:** keybinds call `quickshell:<GlobalShortcut name>` or `qs -c $qsConfig ipc call <target> <fn>`, where `qsConfig="ii"`. Many binds also run a non-shell fallback command. All names and targets are listed in [quickshell/architecture.md](quickshell/architecture.md#ipc-and-global-shortcuts).
- **Shell → Hyprland:** QML dispatches use the Lua form, e.g. `Hyprland.dispatch("hl.dsp.focus({workspace = N})")`. The shell writes its own Hyprland settings to Lua override files (`hyprland/shellOverrides`). The cheatsheet reads binds from `hyprctl binds -j`.
- **Layer namespaces ↔ rules:** panels use `quickshell:<name>` layer namespaces, and `dots/.config/hypr/hyprland/rules.lua` matches on them. If you rename a namespace, its blur/animation rules silently stop applying.
- **Theming:** a wallpaper change runs `scripts/colors/switchwall.sh` → matugen → JSON/templates under `~/.local/state/quickshell/user/generated/`. The QML shell watches the JSON. Terminals get a separate Python-generated palette. See [dotfiles-and-theming.md](dotfiles-and-theming.md).
- **Settings app ↔ shell:** `settings.qml` runs as a separate `qs -p` process. The two share state only through `config.json`, which the main shell watches.

## Conventions

- **QML imports:** there are no `qmldir` files. Directories are imported as `qs.<path>` (e.g. `qs.modules.common`, `qs.services`). `GlobalStates` comes from `import qs`. A file becomes a singleton through `pragma Singleton`.
- **Formatting:** `qmlformat` settings live in `dots/.config/quickshell/ii/.qmlformat.ini` (4-space indent, 110 columns).
- **User customizations:** they belong in `~/.config/hypr/custom/*.lua` and `config.json`. Don't make users edit the defaults, because the installer overwrites them.
- **Commit messages:** use a short area prefix such as `hypr: …`, `gentoo: …` or `qs: …`.

## Known gotchas and suspected bugs (found while writing these docs)

- **Submodule:** `modules/common/widgets/shapes` is a git submodule. If it isn't initialized (`git submodule update --init`), `MaterialShape`/`MaterialCookie` fail to load. The installer initializes it, but a fresh clone doesn't.
- **Cache wipe on start:** `Directories.qml` deletes and recreates several cache/temp dirs on every start, including when a standalone `qs -p` app starts.
- **Lazy singletons:** services start the first time something references them. A service that must run at startup needs an explicit reference such as `X.load()` in `shell.qml`.
- **Hard-coded bar layout:** the ii bar's layout is fixed in `modules/ii/bar/BarContent.qml`, and `verticalBar/VerticalBarContent.qml` duplicates it. No config option lists the bar widgets.
- **Family-specific shortcuts:** many GlobalShortcut names are only implemented by the ii family, so under waffle they do nothing. Waffle does reuse five ii modules (cheatsheet, OSK, overlay, screen translator, wallpaper selector). Switching families: `Ctrl+Super+P`. `modules/waffle/README.md` says Super+Alt+W, which is stale.
- **Suspected bug (notifications):** `Config.qml` declares `notifications.monitor.*`, but the notification popup and the settings page use `notifications.forceMonitor.*`, so the setting probably isn't saved.
- **Unverified (`TEST_ALIVE`):** keybind fallbacks use `qs ipc call TEST_ALIVE || <fallback>`, but no `TEST_ALIVE` target exists in the repo. Whether the fallback is suppressed depends on how `qs` exits.
- **Unverified (duplicate `search` target):** in waffle, both `WaffleTaskView.qml` and `WaffleStartMenu.qml` declare the `search` IPC target.
- **Stale translation-tool paths:** `translations/tools/` docs and defaults point to `.config/quickshell/translations`. Only `manage-translations.sh` resolves paths correctly.
- **No config migration:** nothing migrates renamed or removed `Config.options` keys.
- **Installer:** the legacy (default) install replaces the whole Quickshell config dir, and the experimental YAML install doesn't record files for uninstall.

## Maintaining these docs

When you change behavior that a doc describes, update that doc in the same commit. Keep the docs dense and cite paths, and mark anything you couldn't verify as `unverified`.
