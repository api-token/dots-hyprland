# Dotfiles and Material You theming

## Purpose and scope

This document covers `dots/` outside `dots/.config/{hypr,quickshell}/`, plus the Quickshell color scripts needed to explain wallpaper-to-application theming. `dots/` mirrors files installed into the user's home; repository paths are sources, not the live configuration. See [Hyprland](hyprland.md), [Quickshell configuration and common code](quickshell/config-and-common.md), and [setup and installation](setup-and-install.md).

Generated runtime state such as `~/.local/state/quickshell/user/generated/colors.json` is **not in this repository**. Some generated-output locations under `~/.config/` have checked-in initial versions (Hyprland colors, Hyprlock colors, Fuzzel colors); wallpaper generation replaces the installed copies. Do not confuse those initial versions with the templates that control future generations.

## File map

| Repository path | Role |
| --- | --- |
| `dots/.config/matugen/config.toml` | Active template-to-output manifest. |
| `dots/.config/matugen/templates/` | Material color templates for QML JSON, compositor/lock, GTK, Fuzzel, KDE seed and wallpaper path; also inactive AGS templates. |
| `dots/.config/kitty/` | Fish terminal, generated palette include, search kitten and mark navigation helper. |
| `dots/.config/foot/foot.ini` | Fish terminal, fonts/padding, keyboard/search bindings; includes `custom/foot.ini` last. |
| `dots/.config/foot/custom/foot.ini` | Commented template for user overrides; the installer never overwrites an existing copy. |
| `dots/.config/fish/` | Interactive startup, Starship, terminal color replay, aliases, universal variables and optional TTY launcher. |
| `dots/.config/zshrc.d/` | Zsh snippets for color replay, keybindings and optional TTY launcher. |
| `dots/.config/starship.toml` | Prompt using palette indices modified by generated terminal themes. |
| `dots/.config/fuzzel/` | Standalone launcher/dmenu and generated colors. |
| `dots/.config/wlogout/` | Fallback session menu actions and static CSS. |
| `dots/.config/Kvantum/` | Static MaterialAdw and Colloid Qt widget themes; Kvantum selection is MaterialAdw. |
| `dots/.config/kde-material-you-colors/config.conf` | External KDE color generator options. |
| `dots/.config/{kdeglobals,darklyrc,dolphinrc,konsolerc}` | KDE colors/fonts/widget style and application preferences. |
| `dots/.config/fontconfig/fonts.conf` | Disable font subpixel rendering. |
| `dots/.config/mpv/mpv.conf` | Keep media player open after playback. |
| `dots/.config/xdg-desktop-portal/hyprland-portals.conf` | Portal backend preference and KDE file chooser. |
| `dots/.config/{chrome,code,thorium}-flags.conf` | Application launcher flags. |
| `dots/.local/share/icons/illogical-impulse.svg` | Project icon asset. |
| `dots/.local/share/konsole/Profile 1.profile` | Fish/truecolor profile selecting `MaterialYou` colors. |
| `dots/.local/share/kxmlgui5/konsole/sessionui.rc` | Konsole menus/toolbar/context menu and copy/paste shortcuts. |

## End-to-end color pipeline

### 1. Wallpaper or palette request

The shared shell service calls `scripts/colors/switchwall.sh --mode dark|light --image PATH` from `Wallpapers.apply()` (`dots/.config/quickshell/ii/services/Wallpapers.qml:42`). Its fallback chooser calls the same script without `--image` (`:38`). Light/dark toggling calls `switchwall.sh --mode ... --noswitch` (`services/MaterialThemeLoader.qml:76`). The Hyprland wallpaper shortcuts dispatch shell globals and include a script fallback; see [Hyprland](hyprland.md).

`dots/.config/quickshell/ii/scripts/colors/switchwall.sh:3` uses:

- Shell files: `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii` (the script hardcodes config name `ii`).
- User settings: `$XDG_CONFIG_HOME/illogical-impulse/config.json`.
- Runtime state: `${XDG_STATE_HOME:-$HOME/.local/state}/quickshell`.
- Runtime cache: `${XDG_CACHE_HOME:-$HOME/.cache}/quickshell`.
- Python environment: `$ILLOGICAL_IMPULSE_VIRTUAL_ENV`, normally `~/.local/state/quickshell/.venv`, exported by `dots/.config/hypr/hyprland/env.lua:16`.

Supported request arguments are `--mode`, `--type`, `--color`, `--image`, `--noswitch`, or a positional image path (`switchwall.sh:345`). With no path/accent/`--noswitch`, KDialog selects a file, starting in Pictures/Wallpapers/showcase, Wallpapers, or Pictures (`:411`).

Palette settings come from `appearance.palette.type` and `appearance.palette.accentColor` in the user JSON (`:327`). `--color` stores a hex accent, clears it with `clear`, or invokes Hyprpicker; selecting a new image clears the fixed accent (`:418`). `--noswitch` obtains the current wallpaper from JSON; it is used for recoloring but still traverses the common wallpaper-processing function.

Eight explicit scheme types are accepted: content, expressive, fidelity, fruit-salad, monochrome, neutral, rainbow, tonal-spot (all prefixed `scheme-`), plus `auto` (`:398`). For `auto`, `scheme_for_image.py:32` selects neutral below colorfulness 40, otherwise tonal-spot; it uses OpenCV/NumPy and downsizes to a maximum dimension of 128. Failure falls back to tonal-spot. The Python/KDE helpers also know vibrant, but `switchwall.sh`'s validation list does not accept it.

### 2. Update wallpaper state and determine inputs

For a static image, the script kills existing mpvpaper processes, updates `.background.wallpaperPath` in the existing settings JSON using `jq` + temp-file rename, and replaces the video restore script with a stub (`switchwall.sh:144`, `:253`). The shell watches config changes (`modules/common/Config.qml:64`). The ii background reads that option, substituting the thumbnail for video (`modules/ii/background/Background.qml:43`); waffle directly reads `wallpaperPath` (`modules/waffle/background/WaffleBackground.qml:40`).

Video extensions recognized by the script are mp4/webm/mkv/avi/mov (`switchwall.sh:109`). It launches `mpvpaper` per monitor with looping, no audio and hardware decoding, extracts the first frame via FFmpeg to `~/.config/hypr/custom/scripts/mpvpaper_thumbnails/`, stores `background.thumbnailPath`, and generates `custom/scripts/__restore_video_wallpaper.sh` for compositor startup (`:198`). Color generation uses the extracted frame, not the video file. This means the generated Matugen wallpaper-path file can contain the thumbnail path.

The script optionally asks Gemini to categorize the wallpaper and writes `user/generated/wallpaper/category.txt` when `background.widgets.clock.cookie.aiStyling` is enabled (`:158`). It also offers an Upscayl action for low-resolution images if ImageMagick `identify` is available (`:62`).

If `--mode` is absent, the GNOME interface color-scheme setting chooses dark only for `prefer-dark`, otherwise light (`:262`). A requested light/dark mode can select sibling `NAME-dark.ext` / `NAME-light.ext` variants when present (`:448`). `pre_process()` sets GNOME `color-scheme` and `gtk-theme` to `prefer-dark`/`adw-gtk3-dark` or `prefer-light`/`adw-gtk3` (`:37`).

### 3. Generate app/shell colors with Matugen

`switchwall.sh:184` constructs `matugen --source-color-index 0 image PATH` or `color hex COLOR`, then supplies `--mode` and `--type`. At `:306` it runs Matugen, which renders the active manifest below. These templates use `{{colors.ROLE.default.hex}}`, `.hex_stripped`, `.light`, `.dark`, etc.; the JSON template emits snake_case role keys.

The gate `appearance.wallpaperTheming.enableAppsAndShell=false` returns **before both generators, terminal application and KDE/editor postprocessing**, after wallpaper changes and GNOME theme preprocessing (`:287`). Terminal-only enablement does not bypass this outer gate.

### 4. Generate and apply a separate terminal palette

After Matugen, the script activates the Python venv and runs `generate_colors_material.py`, redirecting stdout to `$STATE_DIR/user/generated/material_colors.scss` (`switchwall.sh:307`). This is a second generator, not a Matugen template output.

`generate_colors_material.py:64` uses Pillow to resize the input, Material You `QuantizeCelebi`/`Score` to select a source color, and the selected `materialyoucolor.scheme` class to produce Material roles. A supplied accent bypasses image extraction. `--cache` writes the source hex to `user/generated/color.txt` in the **image** branch (`:79`); therefore this file is first written by Matugen's KDE seed template and may then be overwritten by Python's source selection.

`terminal/scheme-base.json` supplies dark/light terminal base colors. The generator harmonizes their hue toward the Material primary palette key, optionally blends background/foreground, and adjusts tone (`generate_colors_material.py:134`). `switchwall.sh:272` can force terminal dark mode independently of app/shell mode and passes `harmony`, `harmonizeThreshold`, and `termFgBoost` from `appearance.wallpaperTheming.terminalGenerationProps` (`:296`).

`applycolor.sh:24` parses the SCSS-style `$name: value;` output and substitutes placeholders into two templates:

| Generated terminal file under `~/.local/state/quickshell/user/generated/terminal/` | Consumer / live update |
| --- | --- |
| `kitty-theme.conf` | Included by `dots/.config/kitty/kitty.conf:2`; apply script sends SIGUSR1 to existing Kitty processes (`applycolor.sh:30`). |
| `sequences.txt` | OSC escape sequences written to numeric `/dev/pts/*` (`applycolor.sh:51`); replayed on new Fish/Zsh sessions by their startup snippets. |

Terminal application runs only when `enableTerminal=true` if user config exists; a missing config enables it by default (`applycolor.sh:81`). Generation itself already happened. Palette slots 232–255 are remapped to Material roles for the Starship prompt, in addition to the usual 0–15 palette (`scripts/colors/terminal/kitty-theme.conf:26`, `terminal/sequences.txt`). Foot has no generated colors section/include; it receives these escape sequences through its Fish child or live PTY update.

### 5. QML observes generated JSON; KDE/editor updates run separately

`services/MaterialThemeLoader.qml:16` reads `Directories.generatedMaterialThemePath`, watches it (`:61`), converts JSON snake_case names into `Appearance.m3colors.m3CamelCase` properties (`:22`), and derives dark mode from background lightness. It retries binding to the generated path after a wallpaper change if the file was initially missing. It uses a configurable delay after changes (`:51`). The generated path is declared in `modules/common/Directories.qml:40`; the producer's default filesystem location is `~/.local/state/quickshell/user/generated/colors.json`.

This QML palette comes from **Matugen JSON**, not `material_colors.scss` or terminal OSC sequences. `Appearance.qml` contains initial/default role colors until generated colors apply. See [Quickshell configuration and common code](quickshell/config-and-common.md) for styling consumers.

`switchwall.sh:53` then backgrounds two postprocessing jobs:

- `handle_kde_material_you_colors()` checks `appearance.wallpaperTheming.enableQtApps`, maps the selected scheme, and invokes `~/.config/matugen/templates/kde/kde-material-you-colors-wrapper.sh` (`:15`). The wrapper reads generated `color.txt`, derives dark/light mode from GNOME settings, maps scheme names to integers, activates the venv and runs `kde-material-you-colors -d|-l --color HEX -sv NUMBER` (`wrapper.sh:5`, `:29`, `:46`).
- `code/material-code-set-color.sh:4` updates `material-code.primaryColor` in existing Code, VSCodium, Code - OSS, Code - Insiders, Cursor, Antigravity and Windsurf user settings. It reads the same generated `color.txt`. The edits use `grep`/`sed`, not a JSONC parser; the corresponding editor extension is an external consumer, not supplied here.

KDE generation is performed by an installed external package. **Unverified:** its complete output-file list and live application reload behavior are not established by source in this repository. The checked-in KDE files and Konsole profile show the intended MaterialYou consumers; do not claim Matugen directly writes `kdeglobals`, Darkly configuration or Kvantum SVGs.

## Matugen manifest: exact active outputs

All template paths in this table are relative to installed `~/.config/matugen/templates/`; outputs are literal manifest paths (`dots/.config/matugen/config.toml:4`).

| Template | Output | Reader |
| --- | --- | --- |
| `colors.json` | `~/.local/state/quickshell/user/generated/colors.json` | QML `MaterialThemeLoader` → `Appearance.m3colors`. |
| `hyprland/colors.lua` | `~/.config/hypr/hyprland/colors.lua` | Lua compositor entry requires it before custom config. |
| `hyprland/hyprlock-colors.conf` | `~/.config/hypr/hyprlock/colors.conf` | `hyprlock.conf` sources it. |
| `fuzzel/fuzzel_theme.ini` | `~/.config/fuzzel/fuzzel_theme.ini` | Included by `fuzzel.ini`. |
| `gtk-3.0/gtk.css` | `~/.config/gtk-3.0/gtk.css` | GTK3 user CSS: accents, surfaces, view/popup colors. |
| `gtk-4.0/gtk.css` | `~/.config/gtk-4.0/gtk.css` | GTK4 user CSS with light and dark `prefers-color-scheme` sections. |
| `kde/color.txt` | `~/.local/state/quickshell/user/generated/color.txt` | KDE wrapper and editor color script; Python may overwrite it later. |
| `wallpaper.txt` | `~/.local/state/quickshell/user/generated/wallpaper/path.txt` | `kde-material-you-colors/config.conf:13`. |

`templates/ags/{_material.scss,sourceviewtheme.xml,sourceviewtheme-light.xml}` exist but **have no active entries** in this manifest. Do not expect running Matugen to render them. Likewise the terminal templates live under Quickshell scripts, not the Matugen template directory.

The manifest hardcodes `~/.config` / `~/.local/state` even though shell scripts honor XDG overrides. Kitty/Fish/Zsh includes and KDE config also hardcode the default state path. Supporting a different XDG layout requires changing all producers and consumers, not just an environment variable.

## Terminals, shells and prompt

### Kitty and Foot

`kitty/kitty.conf` selects JetBrains Mono Nerd Font size 11, a beam cursor/trail, margin 21.75, no OS-window close confirmation and `shell fish`. Ctrl+C is `copy_or_interrupt`, page keys scroll, and Ctrl plus/minus/zero adjusts font size. Ctrl+F launches a horizontal split with the local search kitten (`kitty.conf:25`).

`kitty/search.py` is vendored from `trygveaa/kitty-kitten-search` (GPLv3 header): a TUI search using Kitty remote control and cached search text. It calls adjacent `scroll_mark.py` for previous/next marks (`search.py:57`, `:260`). Keep both helper files together when changing or installing the search binding.

`foot/foot.ini` selects Fish, `xterm-256color`, JetBrainsMono Nerd Font size 11, fixed DPI behavior, padding 25×25, 10,000 scrollback lines and a non-blinking beam cursor. Ctrl+C/Ctrl+V copy/paste; Ctrl+Shift+C explicitly sends byte `\x03` (interrupt); Ctrl+F opens search, with F3/Shift+F3 navigation. There is no static Material palette in this file. Its last line is `include=~/.config/foot/custom/foot.ini` (under a re-declared `[main]`), so user settings there override the defaults. Foot treats a missing include as a config error, which is why the installer always seeds that file. A key combo can only be bound once: to reuse one (e.g. `clipboard-copy=Control+Shift+c`), first unbind the default (`[text-bindings]` `\x03=none`). Validate with `foot --check-config`.

### Fish and Zsh

`fish/config.fish:2` runs its setup only for interactive sessions:

- Disable greeting, initialize Starship and transient prompt unless `$TERM=linux`.
- Replay generated `terminal/sequences.txt` if present (`:16`).
- Alias `clear` and typo variants to explicit escape sequences; `pamcan` → pacman; `q` → `qs -c ii`; graphical-terminal `ls` → eza; Kitty-only `ssh` → `kitten ssh`.

`fish/fish_variables` is Fish's universal-variable serialization, containing syntax/pager colors, default key bindings and Fisher plugin metadata. It names Fisher but does not include Fisher's implementation; do not interpret metadata as a bundled plugin installation.

`fish/auto-Hypr.fish` and `zshrc.d/auto-Hypr.sh` run `exec start-hyprland` when DISPLAY is empty and `XDG_VTNR=1`, logging to `~/.cache/hyprland.log`. **Unverified:** the checked-in Fish config does not source `auto-Hypr.fish`, and no top-level `.zshrc` is shipped here. These are snippets, not evidence that automatic TTY startup or Zsh sourcing is enabled on every installation.

`zshrc.d/dots-hyprland.zsh` replays generated terminal sequences if present; `shortcuts.zsh` binds Ctrl+H to backward-kill-word and Ctrl+Z to undo. There is no Zsh Starship initialization in these shipped snippets.

`starship.toml:12` defines a two-line prompt of command duration, directory, git branch, then the character. Module styling uses indexed colors (e.g. 235/240/243/244/252/255), intentionally recolored by terminal templates. Defining username, host, git-status or other modules later in the file does not insert them into this explicit top-level format. Change the terminal role mapping if changing the meaning of these slots.

## GTK, Qt and KDE

GTK generation is user CSS, plus GNOME interface preferences set by `switchwall.sh`; no `gtk-3.0` or `gtk-4.0` output tree is shipped in `dots/`. GTK3's template uses the selected default scheme; GTK4's template contains both light/dark sections. Whether an already-running third-party app reloads these files is application-dependent and unverified here.

Qt is directed toward the KDE platform theme by `dots/.config/hypr/hyprland/env.lua:11`. `kdeglobals:135` ships MaterialYouDark colors, Google Sans Flex UI fonts, JetBrainsMono fixed font, a Kitty terminal preference, Breeze-dark icons, and `widgetStyle=Darkly` (`:151`). `darklyrc` disables widget shadows. `dolphinrc` sets full paths, full-width status bar, no menu bar and a broad preview-plugin list; those plugins are preferences, not bundled binaries.

`kde-material-you-colors/config.conf` points wallpaper detection to generated `wallpaper/path.txt`, uses scheme variant 5, disables pywal integration, provides seven custom text colors, and selects `breeze-plus`/`breeze-plus-dark` for light/dark icon themes (`:13`, `:19`, `:34`, `:41`, `:69`). The wrapper supplies explicit seed color, mode and scheme on each run.

`Kvantum/kvantum.kvconfig` selects MaterialAdw. `Kvantum/MaterialAdw/` and `Kvantum/Colloid/` each pair widget-style `.kvconfig` data with SVG assets; Colloid includes light/dark variants. These have literal color values (`MaterialAdw.kvconfig:79`) and are not Matugen outputs. The shipped KDE widget style is Darkly, so merely including Kvantum themes does not establish that Qt apps use them.

`konsolerc` selects `Profile 1.profile` and single-instance mode. `dots/.local/share/konsole/Profile 1.profile` requests the `MaterialYou` color scheme, `/bin/fish`, and `COLORTERM=truecolor`; the actual `.colorscheme` file is not bundled. `kxmlgui5/konsole/sessionui.rc` supplies menus/toolbars and Ctrl+C/Ctrl+V copy/paste overrides (`:88`). Installer choice affects which of these files reaches HOME; see [setup and installation](setup-and-install.md).

## Remaining desktop files

- `fuzzel/fuzzel.ini:1` includes generated colors, uses Google Sans Flex medium, `kitty -1` as terminal, overlay layer, a `>>` prompt, rounded border and immediate exit for empty dmenu input. Fuzzel is also the emergency search/clipboard/emoji UI when shell integration fails.
- `wlogout/layout` defines lock/hibernate/logout/shutdown/suspend/reboot. Lock uses loginctl; logout/shutdown/reboot first kill Hyprland client PIDs. `style.css` uses Material Symbols Outlined glyph names as large button labels and fixed translucent colors; it has no Matugen output entry.
- `fontconfig/fonts.conf:4` sets font `rgba=none` (no RGB subpixel layout). Font families are selected separately by terminal, KDE, Fuzzel and shell configs; this file installs no fonts.
- `mpv/mpv.conf` contains only `keep-open=yes`. Video-wallpaper mpvpaper options are specified separately in `switchwall.sh:107`.
- `xdg-desktop-portal/hyprland-portals.conf` prefers `hyprland;gtk`, overriding `org.freedesktop.impl.portal.FileChooser=kde`. The KDE chooser's float/size rules are in `dots/.config/hypr/hyprland/rules.lua:48`.
- `chrome-flags.conf` requests GNOME libsecret password storage, Wayland hint, GTK4, GPU-blocklist override, touchpad history, Wayland IME and disables `ExtensionManifestV2Unsupported`. `code-flags.conf` has the same general platform/input flags without that manifest flag. Thorium has libsecret/GTK4/GPU/touchpad flags, with its Wayland hint commented out. These are launcher-consumed preferences; support by each installed application's wrapper is unverified.
- `.local/share/icons/illogical-impulse.svg` is the project logo, not a generated icon theme. `.local/share/konsole/` and `.local/share/kxmlgui5/konsole/` are application data described above. These are all the checked-in `.local/share/` subtrees in `dots/`.

## Common changes

### Change an app's generated colors

1. Find its active mapping in `dots/.config/matugen/config.toml`; edit the corresponding template, not the installed output or repository's sample generated colors.
2. Preserve consumer syntax: stripped hex + alpha for Hyprland/Fuzzel, `#hex` for GTK/JSON, dollar-prefixed variables in Hyprlock.
3. Deploy the edited template (and `config.toml` if changed) to `~/.config/matugen/`; the installer copies rather than symlinks, and Matugen reads the installed templates.
4. In a configured desktop, recolor the current wallpaper with `~/.config/quickshell/ii/scripts/colors/switchwall.sh --noswitch`. This writes multiple application configs and may launch wallpaper processing; it is not a pure template check. Do not run it during documentation-only work.
5. Inspect generated files first, then confirm the relevant consumer refreshed. QML watches its JSON; Kitty is explicitly signaled; compositor/GTK/KDE reload timing must be checked in the target session.

### Add a newly themed application

1. Add a consumer-specific template below `dots/.config/matugen/templates/` and a `[templates.NAME]` entry with exact input/output paths.
2. Configure the application to read the output, ideally through an include rather than overwriting unrelated preferences.
3. If it needs an explicit reload, follow `applycolor.sh` or `switchwall.sh` postprocessing patterns; Matugen's current manifest defines no hooks.
4. Document any new generator dependencies and generated paths. Do not commit personal runtime state, wallpaper thumbnails or installed output snapshots.

### Change terminal harmony, prompt or static desktop defaults

1. For personal palette behavior, use `appearance.wallpaperTheming.terminalGenerationProps` in the shell settings JSON/settings UI; for shared defaults/algorithms, inspect the generator and [Quickshell configuration](quickshell/config-and-common.md).
2. For base terminal colors, edit `scripts/colors/terminal/scheme-base.json`; for role-to-slot mapping, edit `terminal/kitty-theme.conf` **and** `terminal/sequences.txt` so Kitty and other terminals agree.
3. For prompt layout, edit `dots/.config/starship.toml`; keep its palette-slot dependency in mind.
4. For static preferences, edit the matching `dots/.config/` source, then check install copy policy. Unlike Hyprland's custom modules, these directories do not universally offer protected override layers. The experimental manifest distinguishes `sync` directories from `soft` individual files (`sdata/subcmd-install/3.files-exp.yaml:70`, `:98`).

## Pitfalls and verification limits

- A wallpaper can change while colors stay unchanged: the outer `enableAppsAndShell` gate returns after updating wallpaper/config and GNOME theme settings.
- `enableTerminal=false` skips terminal application, not terminal palette generation. `enableQtApps=false` only skips the KDE wrapper; editor postprocessing still runs.
- Matugen JSON and terminal Python extraction can select slightly different source colors. `color.txt` is shared between stages; avoid treating it as immutable Matugen output.
- Generated paths may be required before first use: Kitty includes a state file absent from the repository, and the KDE profile references an externally generated scheme. Check setup-created runtime state rather than assuming repository files suffice.
- The shell script does not enable `set -e`; failure of one generator is not a transactional rollback of earlier wallpaper/config writes. KDE/editor and terminal application also run asynchronously.
- The main color scripts do not explicitly reload Hyprland or restart GTK applications. Runtime reload behavior and exact external KDE package outputs remain unverified; no shell, compositor, color generation or desktop preferences were changed while writing this document.
