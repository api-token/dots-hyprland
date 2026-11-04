# Hyprland configuration

## Purpose and scope

`dots/.config/hypr/` is installed as `~/.config/hypr/`. The compositor entry point is **Lua**, `hyprland.lua`, using the `hl.*` API; do not add legacy `bind = ...` or `windowrule = ...` lines to Lua modules. This is the Hyprland 0.55 Luaification configuration (`.github/README.md:21`). Hypridle and Hyprlock still use their own `.conf` syntax. See [dotfiles and theming](dotfiles-and-theming.md) for generated colors and [Quickshell architecture](quickshell/architecture.md) for the desktop shell.

Paths below are repository-relative unless prefixed with `~/` or `$`. No compositor or shell was launched to verify runtime behavior.

## Key files and ownership

| Path under `dots/.config/hypr/` | Responsibility |
| --- | --- |
| `hyprland.lua` | Ordered `require()` entry point. |
| `hyprland/lib/init.lua` | Global `HOME`, file helpers, workspace-group calculation. |
| `hyprland/services/init.lua`, `services/create_custom_config.lua` | Register startup creation of missing custom modules. |
| `hyprland/env.lua` | Session environment. |
| `hyprland/variables.lua` | App launch commands, `qsConfig`, workspace group size; loaded by keybinds. |
| `hyprland/execs.lua` | Startup processes in a `hyprland.start` callback. |
| `hyprland/general.lua` | Monitor fallback, gestures, layout, decoration, animations, input and cursor settings. |
| `hyprland/rules.lua` | Window, workspace and layer-surface rules. |
| `hyprland/keybinds.lua` | Bind definitions and shell integration. |
| `hyprland/colors.lua` | Matugen output; repository ships initial colors. |
| `hyprland/shellOverrides/main.lua` | Shell-managed settings, loaded last; do not hand-edit. |
| `custom/{env,variables,execs,general,rules,keybinds}.lua` | Installed user's persistent overrides/additions. |
| `custom/scripts/__restore_video_wallpaper.sh` | Generated video-wallpaper restoration command, initially a stub. |
| `hyprland/scripts/` | App fallback launcher, emoji picker, screenshot search, GeoClue and local AI utilities. |
| `hypridle.conf` | Lock, display power and suspend policy. |
| `hyprlock.conf`, `hyprlock/` | Fallback lock screen, generated colors and status helpers. |

## Load order and lifecycle

The exact sequence is `dots/.config/hypr/hyprland.lua:5`:

1. `hyprland.lib`, then `hyprland.services`.
2. Default `hyprland.env`, then optional `custom.env`.
3. Defaults: `hyprland.execs`, `general`, `rules`, `colors`, `keybinds`, in that order.
4. Optional `custom.execs`, `general`, `rules`, `keybinds`, in that order.
5. Optional top-level `workspaces.lua`, then `monitors.lua` (labeled nwg-displays support).
6. `hyprland.shellOverrides.main`, unconditionally, last.

`custom.variables` is an exception to the visible entry-point sequence: `hyprland/keybinds.lua:1` requires defaults from `hyprland.variables` and immediately requires optional `custom.variables`, before constructing binds. These values are Lua globals (`terminal`, `browser`, `workspaceGroupSize`, etc.); `qsConfig` is instead exported with `hl.env("qsConfig", "ii")` in `hyprland/variables.lua:5`.

Consequences:

- User environment is set before default startup callbacks are registered. App command overrides are evaluated before binds capture those commands.
- Ordinary custom settings load after their defaults, but generated shell overrides and optional monitor/workspace modules load later still.
- A later bind declaration is not evidence that an earlier bind was removed. Defaults deliberately register multiple actions on the same key (global shortcut plus fallback command).
- A new custom filename is not auto-discovered. Add code to an already-required module, or explicitly `require()` the new module from one of those files.

`hyprland/lib/init.lua:3` implements `is_file_exists` with `io.open`. `create_if_not_exists` creates the parent directory and writes a comment-only stub without overwriting an existing file (`:13`). The service registers `hl.on("hyprland.start", ...)` to ensure all six custom modules exist; notification and reload lines are commented out (`hyprland/services/create_custom_config.lua:3`). This is startup scaffolding, not a migration engine.

Custom files are the update-friendly location. The legacy installer preserves the custom directory (`sdata/subcmd-install/3.files-legacy.sh:75`); the experimental manifest excludes it from the default sync and uses `skip-if-exists` (`sdata/subcmd-install/3.files-exp.yaml:46`). See [setup and installation](setup-and-install.md) for installer details.

## Defaults, environment and shell-owned settings

`hyprland/general.lua` supplies an unnamed-output fallback monitor (`preferred`, `auto`, scale 1), three-finger move/pinch gestures, four-finger workspace/overview gestures, gaps and borders, rounded corners, blur/shadows, dwindle settings, animation curves, US keyboard/repeat settings, touchpad behavior, DPMS wake behavior, and XWayland zero scaling. Key entry points are `:2`, `:9`, `:39`, `:118`, and `:255`.

Do not infer final visual behavior from `general.lua` alone: `rules.lua:7` disables blur for all windows, `colors.lua` replaces its initial border colors, and `shellOverrides/main.lua` can override configuration again.

`hyprland/env.lua:4` exports:

- `ELECTRON_OZONE_PLATFORM_HINT=auto`.
- `XDG_DATA_DIRS` with user/system Flatpak export paths plus standard paths and the inherited value.
- `QT_QPA_PLATFORM=wayland;xcb`, `QT_QPA_PLATFORMTHEME=kde`, `XDG_MENU_PREFIX=plasma-`.
- `ILLOGICAL_IMPULSE_VIRTUAL_ENV=$HOME/.local/state/quickshell/.venv`, used by color and other Python scripts.

The initial `shellOverrides/main.lua` contains only a warning. The shell's `services/HyprlandConfig.qml:19` writes it through `scripts/hyprland/hyprconfigurator.py`. The helper accepts colon-separated setting keys, generates one-line nested `hl.config({...})` calls (`hyprconfigurator.py:17`), matches existing lines with regexes, and atomically replaces the file (`:88`). Preserve its generated format; it is not a general Lua parser. See [settings app](quickshell/settings-app.md) for callers.

`hyprland/colors.lua` is also writable runtime output: `dots/.config/matugen/config.toml:8` targets this exact installed file. To change its generated expressions, edit `dots/.config/matugen/templates/hyprland/colors.lua`; to choose a fixed personal border color, use `custom/general.lua`, while accounting for later shell overrides. The template maps outline/surface colors to borders, a dark surface to compositor background, and primary colors to pinned-window borders.

## Keybind structure and Quickshell integration

`hyprland/keybinds.lua` mixes `hl.bind(chord, dispatcher, options)` with Lua callbacks and loops. Dispatcher constructors include `hl.dsp.exec_cmd(...)`, `hl.dsp.global(...)`, `hl.dsp.window.*`, `hl.dsp.focus(...)` and `hl.dsp.workspace.*`. Callbacks dispatch dynamically using `hl.dispatch(...)`; for example, workspace numbers depend on the currently active workspace (`keybinds.lua:199`, `:248`).

Options used in this file include `description`, `locked`, `repeating`, `release`, `transparent`, `ignore_mods`, `mouse`, `non_consuming`, and `submap_universal`. Reuse nearby working patterns rather than translating old Hyprland bind flags mechanically.

Descriptions use `"Category: Action"`. The shell reads **live** `hyprctl binds -j`, collects each description prefix before `:`, and refreshes on `configreloaded` (`dots/.config/quickshell/ii/services/HyprlandKeybinds.qml:20`). Its introductory comment about parsing config comments is stale; the active process is at `:33`. Add a useful description if the bind should appear in the cheatsheet.

Main categories, rather than an exhaustive shortcut list:

| Category / source | Operations |
| --- | --- |
| Shell (`keybinds.lua:12`) | Search, workspace/clipboard/emoji overview, sidebars, cheatsheet, keyboard, media controls, overlay, session menu, bar, wallpaper selection, light/dark, shell restart and panel-family cycle. |
| Utilities (`:60`) | Screenshots, region capture/search/OCR/translation/recording, clipboard history, emoji, color picker and selected-text local AI. |
| Screen (`:108`) | Cursor zoom, clamped to 1–3. |
| Media (`:127`) | Playerctl transport and PipeWire sink/source mute; volume and brightness hardware keys are earlier at `:40`. |
| Window (`:150`) | Focus, move/resize, close/kill, splits, float, maximize/fullscreen, pin, move to workspace/scratchpad. |
| Workspace (`:245`) | Numbered, relative and busy workspace navigation, keypad/keycode aliases, scratchpad. |
| Virtual machines (`:304`) | `virtual-machine` submap; universal `SUPER + ALT + F1` toggles entry/escape. |
| Session (`:334`) | Lock, suspend and poweroff. |
| Apps (`:344`) | Terminal, file manager, browser, editor, office, mixer, settings and task manager, using variables. |

There are two distinct shell protocols:

- **Global shortcuts:** `hl.dsp.global("quickshell:overviewWorkspacesToggle")` activates a QML `GlobalShortcut { name: "overviewWorkspacesToggle" }`; it is not an IPC target name. `modules/ii/overview/Overview.qml:149` defines the search/overview shortcuts. `searchToggleRelease` handles press/release state inside QML (`:173`). Other owners include `modules/ii/sidebarLeft/SidebarLeft.qml:219`, `sidebarRight/SidebarRight.qml:86`, `regionSelector/RegionSelector.qml:93`, and common `panels/lock/LockScreen.qml:114`.
- **Command IPC:** the prefix is `qs -c $qsConfig ipc call` (`keybinds.lua:9`). Brightness uses target `brightness` and functions `increment`/`decrement` (`services/Brightness.qml:248`); clipboard watchers call target `cliphistService`, function `update` (`services/Cliphist.qml:150`). Target/function names come from `IpcHandler`, not `GlobalShortcut.name`.

The shell loads either the `ii` or `waffle` family (`dots/.config/quickshell/ii/shell.qml:45`). Some shortcut names are intentionally shared by the families; inspect the active family's implementation when changing behavior. Panel-family cycling is available as global `panelFamilyCycle` and IPC `panelFamily cycle` (`shell.qml:62`).

Several keys register a global action and an external fallback on the same chord. The fallback string starts with `qs -c $qsConfig ipc call TEST_ALIVE`, then `||` runs Fuzzel, wlogout, Hyprshot, scripts, etc. (`keybinds.lua:10`). **Unverified:** no `TEST_ALIVE` handler was found in checked-in Quickshell sources. Do not assume the probe successfully suppresses fallbacks in a running session.

`workspace_in_group(i)` calculates `floor((active.id - 1) / workspaceGroupSize) * workspaceGroupSize + i` (`hyprland/lib/init.lua:22`); the default group size is 10. The default numbered-bind loops also run 1–10, so changing the group size alone does not resize those loops.

## Rules

`hyprland/rules.lua` uses explicit Lua tables:

- `hl.window_rule({ match = { class = "regex", title = "regex" }, ... })` for client behavior. Defaults float/center dialogs and utility apps, place picture-in-picture and sharing windows, suppress maximize requests, enable immediate presentation for selected games, and remove tiled-window shadows (`:9`, `:53`, `:61`, `:66`, `:79`).
- `hl.workspace_rule(...)` sets scratchpad outer gaps (`:88`).
- `hl.layer_rule({ match = { namespace = "regex" }, ... })` controls layer-shell surfaces, not client windows (`:91`). `quickshell:.*` gets blur/popups and alpha handling, with per-panel exceptions and animations (`:134`). Background blur is disabled, and tooltips/overlays have special alpha rules.

Match the correct object: a Quickshell panel generally needs a namespace layer rule, whereas settings dialogs and ordinary applications need window rules. Lua string regex backslashes must be doubled; see the literal class pattern `^dev\\.warp\\.Warp$` in `rules.lua:64`.

## Startup processes and helper scripts

`hyprland/execs.lua:2` puts startup-only work in `hl.on("hyprland.start", function() ... end)`. Its registered commands are:

| Command | Role |
| --- | --- |
| `start_geoclue_agent.sh` | Start a GeoClue demo agent from known distro/Nix locations if absent. |
| `qs -c $qsConfig` | Desktop shell, including bar/background. |
| `custom/scripts/__restore_video_wallpaper.sh` | Restore mpvpaper for a previous video wallpaper. |
| `gnome-keyring-daemon --start --components=secrets` | Secret service. |
| `hypridle` | Lock/idle policy below. |
| `dbus-update-activation-environment --all` and delayed `--systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP` | Propagate session environment. |
| `easyeffects --hide-window --service-mode` | Audio effects service. |
| Two `wl-paste` watchers (`--type text`, `--type image`) | Store clipboard entries with `cliphist store`, then call `cliphistService update`. |
| `hyprctl setcursor Bibata-Modern-Classic 24` | Cursor theme and size. |

`qsConfig` is set later during file evaluation, before the startup callback executes. There is no default standalone wlogout/Fuzzel autostart; those are bind fallbacks.

Scripts under `hyprland/scripts/`:

| File | Behavior / dependencies |
| --- | --- |
| `launch_first_available.sh:2` | For each command string, checks its first word via `command -v`, then `eval`s and backgrounds the first available candidate. App lists live in `variables.lua:9`. |
| `fuzzel-emoji.sh:4` | Embedded emoji data after `### DATA ###`; Fuzzel selects; `type`, `copy`, or `both` use wtype/wl-copy. |
| `snip_to_search.sh:2` | Grim + Slurp capture to `/tmp/image.png`, upload to `uguu.se`, open Google Lens URL, delete local capture. This sends the captured image off-machine. |
| `start_geoclue_agent.sh:4` | Checks for an existing agent, then searches `/usr/libexec`, `/usr/lib`, user Nix profile and system Nix paths. |
| `ai/primary-buffer-query.sh:13` | Reads up to 2000 characters of primary selection; chooses first detected Ollama model or `llama3.2`; POSTs to localhost:11434 `/api/generate`; displays notification. |
| `ai/show-loaded-ollama-models.sh:73` | Matches running process model blobs against Ollama `/api/tags` and `/api/show`; JSON mode `-j`; adjacent license file is Apache-2.0. |

The video restoration script is regenerated by `dots/.config/quickshell/ii/scripts/colors/switchwall.sh:118`, not a place for user autostarts. Thumbnail files are created alongside it in `custom/scripts/mpvpaper_thumbnails/`.

## Idle and lock behavior

`hypridle.conf:1` sends the `quickshell:lock` global dispatch and falls back to Hyprlock if `pidof qs quickshell hyprlock` finds none. This checks process presence, not whether Quickshell's lock module is functioning. `before_sleep_cmd` calls `loginctl lock-session`; resume dispatches `quickshell:lockFocus` to repair focus; `inhibit_sleep=3` is set. Listeners lock after 300 seconds, disable DPMS after 600 (restore on activity), and suspend after 900 using `systemctl suspend || loginctl suspend`.

The preferred lock UI is Quickshell's common lock panel (`modules/common/panels/lock/LockScreen.qml:103`: IPC `lock activate`/`lock focus`, globals `lock`/`lockFocus`). `hyprlock.conf` is the fallback: plain background, password input, keyboard layout, caps-lock warning, time/date, username and battery label. It sources generated `hyprlock/colors.conf` at line 1. `hyprlock/check-capslock.sh` parses the main keyboard from `hyprctl devices`; `hyprlock/status.sh` reads `/sys/class/power_supply/*`.

The Matugen Hyprlock template emits `$background_image`, but the shipped `hyprlock.conf:3` uses only a solid color. Generating that variable alone does not display a wallpaper.

## Common changes

### Add a personal keybind

1. Edit installed `~/.config/hypr/custom/keybinds.lua`; use defaults in `hyprland/keybinds.lua` as API examples.
2. For an external app, use e.g. `hl.bind("SUPER + F9", hl.dsp.exec_cmd("my-app"), { description = "App: My app" })`.
3. For a shell action, find its QML `GlobalShortcut.name` or `IpcHandler.target` and function; choose the corresponding protocol above. Avoid assigning a chord already used by multiple defaults unless combined behavior is intentional.
4. In an actual session, inspect `hyprctl binds -j` to verify the live action/description; the cheatsheet refreshes on config reload. Removing/replacing an existing bind requires checking the compositor's installed Lua API; this repository supplies no unbind example.

### Add a window rule

1. Inspect the target's actual class/title in `hyprctl clients -j` in a running session.
2. Add e.g. `hl.window_rule({ match = { class = "^(my-app)$" }, float = true })` to `custom/rules.lua`.
3. For sizes/positions, copy the numeric or monitor-relative string-expression patterns in `hyprland/rules.lua:34` and `:69`.
4. For shell surfaces instead, use `hl.layer_rule` and the actual `quickshell:...` namespace. Check default matches and later generated overrides before broadening a regex.

### Add an autostart or override defaults

1. Add startup-only commands to `custom/execs.lua` inside `hl.on("hyprland.start", function() hl.exec_cmd("my-daemon") end)`; this follows `hyprland/execs.lua:1`.
2. Commands outside that callback run when the module is evaluated; reserve that for work intentionally repeated on config evaluation/reload.
3. Put app variable assignments in `custom/variables.lua`, environment calls in `custom/env.lua`, and `hl.config`/monitor/input changes in `custom/general.lua`.
4. Keep `hyprland/` changes for shared defaults. Keep generated color expressions in Matugen templates and shell settings in the shell's settings workflow. Installed custom files are preserved by the installer; default directories are update-managed.

## Pitfalls

- Do not assume old Hyprland `.conf` instructions apply to this Lua tree. Some comments and external helper defaults still mention older formats (`hyprconfigurator.py:115`).
- Global names, IPC target/function pairs, Lua globals and environment variables are separate namespaces.
- A shell restart bind (`keybinds.lua:56`) kills `ydotool`, `qs` and `quickshell` before restarting; it is broader than a compositor config reload.
- Default rules include old AGS/launcher namespaces as well as current Quickshell namespaces. Their presence does not mean those programs autostart.
- Runtime behavior, dispatch compatibility and automatic compositor reload after generated-color writes remain unverified without a running target session. The color scripts have no explicit `hyprctl reload` step.
