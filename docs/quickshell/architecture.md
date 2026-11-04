# Quickshell shell ("ii"): architecture

Scope: the big picture of the QML desktop shell at `dots/.config/quickshell/ii/` (installed to `~/.config/quickshell/ii/`). Covers entry points, global state, panel families, directory layout, import conventions, IPC/shortcuts, multi-monitor, translations, scripts, runtime deps, and recipes.

Sibling docs (don't duplicate):
- [config-and-common.md](config-and-common.md): `Config`, `Appearance`, `Directories`, `Persistent`, widget library
- [services.md](services.md): `services/*` singletons
- [panels-ii.md](panels-ii.md): `modules/ii/*` (Material family)
- [panels-waffle.md](panels-waffle.md): `modules/waffle/*` (Windows-11-like family)
- [settings-app.md](settings-app.md): `settings.qml` and `modules/settings/*`
- [../hyprland.md](../hyprland.md): keybinds, execs, layer rules that drive the shell

Paths below are relative to `dots/.config/quickshell/ii/` unless they start with `dots/`, `sdata/` or `~`.

## Directory map

| Path | What it is |
|---|---|
| `shell.qml` | Main entry point (`ShellRoot`). Loads one panel family. |
| `settings.qml` | Standalone settings app (`ApplicationWindow`). |
| `welcome.qml` | First-run welcome window (`ApplicationWindow`). |
| `killDialog.qml` | "Kill conflicting programs?" dialog (tray / notification daemons). |
| `ReloadPopup.qml` | Toast shown after a Quickshell reload (success/failure). |
| `GlobalStates.qml` | Singleton holding open/closed flags for panels (`import qs`). |
| `.qmlformat.ini` | qmlformat settings: 4-space indent, no tabs, max 110 columns. |
| `panelFamilies/` | `IllogicalImpulseFamily.qml`, `WaffleFamily.qml`, `PanelLoader.qml`. |
| `modules/common/` | Shared singletons (`Config`, `Appearance`, `Directories`, `Persistent`, `Icons`, `Images`), `functions/`, `models/`, `utils/`, `panels/lock/`, `widgets/`. See [config-and-common.md](config-and-common.md). |
| `modules/ii/` | Material "ii" panels: background, bar, cheatsheet, dock, lock, mediaControls, notificationPopup, onScreenDisplay, onScreenKeyboard, overlay, overview, polkit, regionSelector, screenCorners, screenTranslator, sessionScreen, sidebarLeft, sidebarRight, verticalBar, wallpaperSelector. |
| `modules/waffle/` | Windows-11-like panels + `looks/` (its own widget set and `Looks.qml` styling singleton). `modules/waffle/README.md` is the author's notes. |
| `modules/settings/` | Pages of the settings app (`QuickConfig.qml`, `GeneralConfig.qml`, `BarConfig.qml`, ...). |
| `services/` | Singletons wrapping system state (audio, network, Hyprland, notifications, T3 Code, wallpapers, theme...). |
| `scripts/` | Shell/Python helpers called via `Process`/`execDetached` and from Hyprland binds. |
| `assets/icons/` (+ `fluent/`), `assets/images/default_wallpaper.png` | Static SVG icons (distro logos, AI providers...) and the first-run wallpaper. |
| `translations/*.json`, `translations/tools/` | UI string tables per locale + maintenance scripts. |

## Entry points and how they are launched

All entry files start with `//@ pragma` lines (Quickshell file pragmas): `UseQApplication`, `Env QS_NO_RELOAD_POPUP=1` (disables Quickshell's built-in reload popup; `ReloadPopup.qml` replaces it), `Env QT_QUICK_CONTROLS_STYLE=Basic`, `Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000`. `shell.qml:6` has a commented-out `QT_SCALE_FACTOR` pragma for UI scaling; `settings.qml`/`killDialog.qml` set `QT_SCALE_FACTOR=1`.

| Entry | Launched by | Notes |
|---|---|---|
| `shell.qml` | `qs -c $qsConfig` in `dots/.config/hypr/hyprland/execs.lua:6` (`qsConfig` env = `"ii"`, `dots/.config/hypr/hyprland/variables.lua:5`). Restart bind: `CTRL+SUPER+R` → `killall ydotool qs quickshell; qs -c $qsConfig &` (`keybinds.lua:56`). fish alias `q` = `qs -c ii` (`dots/.config/fish/config.fish:26`). | `-c ii` selects the config dir `~/.config/quickshell/ii`, whose `shell.qml` is the root. |
| `settings.qml` | `settingsApp` var in `variables.lua:16`: `qs -p ~/.config/quickshell/$qsConfig/settings.qml` (first of a fallback list via `launch_first_available.sh`). | `-p` runs a single QML file as its own Quickshell instance. Sets `Config.readWriteDelay = 0` (`settings.qml:76`). Details: [settings-app.md](settings-app.md). |
| `welcome.qml` | `FirstRunExperience.handleFirstRun()` (`services/FirstRunExperience.qml:30`) when `~/.local/state/quickshell/user/first_run.txt` is missing; also bind `SHIFT+SUPER+ALT+Slash` (`keybinds.lua:38`). | Also applies default wallpaper via `switchwall.sh`. Sets `Config.readWriteDelay = 0`. |
| `killDialog.qml` | `ConflictKiller` service (`services/ConflictKiller.qml:43`): `qs -p <killDialog.qml>` when conflicting tray/notification daemons run. | Sets `Config.readWriteDelay = 0; Config.blockWrites = true` (`killDialog.qml:38-39`) then writes `conflictKiller.autoKill*` on "Always". |
| `ReloadPopup.qml` | Instantiated inside `shell.qml` (`ReloadPopup {}`), not launched separately. | Listens to `Quickshell.onReloadCompleted/onReloadFailed`; layer namespace `quickshell:reloadPopup`. Shows 1 s on success, 10 s on failure (hover pauses). |

Separate `qs -p` instances load the same singletons (`Config`, `Translation`, `Appearance`, `MaterialThemeLoader`...) independently and talk to the main shell only through shared files (e.g. `config.json` is watched, so a write from the settings app is picked up by the main shell).

### `shell.qml` startup (`shell.qml:20-58`)
1. `ReloadPopup {}`.
2. `Component.onCompleted`: `MaterialThemeLoader.reapplyTheme()`, `Hyprsunset.load()`, `FirstRunExperience.load()`, `ConflictKiller.load()`, `Cliphist.refresh()`, `Wallpapers.load()`, `Updates.load()`. Other singletons are created lazily on first reference (QML singleton semantics).
3. Two `PanelFamilyLoader` (inline `component` over `LazyLoader`) entries, `active: Config.ready && Config.options.panelFamily === identifier && extraCondition`.
4. `IpcHandler { target: "panelFamily"; cycle() }` and `GlobalShortcut { name: "panelFamilyCycle" }` → `cyclePanelFamily()` which rotates `Config.options.panelFamily` through `families: ["ii", "waffle"]`.

## GlobalStates (`GlobalStates.qml`)

`pragma Singleton`, located at the shell root, so it is imported with `import qs` (166 files do). Plain `bool` flags: `barOpen` (default true), `crosshairOpen`, `sidebarLeftOpen`, `sidebarRightOpen`, `mediaControlsOpen`, `osdBrightnessOpen`, `osdVolumeOpen`, `oskOpen`, `overlayOpen`, `overviewOpen`, `regionSelectorOpen`, `searchOpen`, `screenLocked`, `screenLockContainsCharacters`, `screenUnlockFailed`, `screenTranslatorOpen`, `sessionOpen`, `superDown`, `superReleaseMightTrigger`, `wallpaperSelectorOpen`, `workspaceShowNumbers`.

- Side effect: opening the right sidebar calls `Notifications.timeoutAll()` + `markAllRead()` (`GlobalStates.qml:33`).
- Owns the `workspaceNumber` GlobalShortcut (press/release sets `superDown`; bound to bare `SUPER_L/R` in `keybinds.lua:17-21`).
- Convention: panels bind visibility/loader `active` to a flag here; IPC handlers/shortcuts flip the flag. Some panels instead keep a local `Loader.active` (e.g. `modules/ii/cheatsheet/Cheatsheet.qml` uses `cheatsheetLoader.active`). Panel-local context singletons (e.g. `modules/ii/overlay/OverlayContext.qml`, `modules/waffle/actionCenter/ActionCenterContext.qml`) also share state with anything that imports their directory.
- Not persisted. Persisted state lives in `Persistent.states` (`~/.local/state/quickshell/states.json`), user options in `Config.options`.

## Panel families

A "panel family" is a complete set of top-level panels. Exactly one is active, chosen by `Config.options.panelFamily` (`"ii"` default, or `"waffle"`; `modules/common/Config.qml:81`).

- `panelFamilies/IllogicalImpulseFamily.qml` → `Scope` of `PanelLoader`s for all `modules/ii/*` panels. Conditional ones: `Bar` (`!Config.options.bar.vertical`), `VerticalBar` (`bar.vertical`), `Dock` (`dock.enable`).
- `panelFamilies/WaffleFamily.qml` → `WaffleActionCenter`, `WaffleBar`, `WaffleBackground`, `WaffleLock`, `WaffleNotificationCenter`, `WaffleNotificationPopup`, `WaffleOSD`, `WafflePolkit`, `WScreenSnip`, `WaffleStartMenu`, `WaffleSessionScreen`, `WaffleTaskView`, plus **fallbacks reused from ii**: `Cheatsheet`, `OnScreenKeyboard`, `Overlay`, `ScreenTranslator`, `WallpaperSelector`. `WaffleOverlay` is commented out.
- `panelFamilies/PanelLoader.qml`: `LazyLoader { property bool extraCondition: true; active: Config.ready && extraCondition }`. Nothing is created until `config.json` is loaded.
- Switching: `CTRL+SUPER+P` → `quickshell:panelFamilyCycle` (`keybinds.lua:58`), or `qs -c ii ipc call panelFamily cycle`, or edit `panelFamily` in config. The outer `LazyLoader` deactivates and destroys the whole family, then builds the other one; services (singletons) survive. (`modules/waffle/README.md` says Super+Alt+W; the actual bind is Ctrl+Super+P.)

### Lazy loading levels
1. Family: `PanelFamilyLoader` in `shell.qml`.
2. Panel: `PanelLoader` (Config ready + `extraCondition`). Instantiated for the whole session once the family is active.
3. Window/content inside the panel: each panel decides. Patterns seen:
   - `LazyLoader { active: GlobalStates.barOpen && !GlobalStates.screenLocked; component: PanelWindow {...} }` per screen (`modules/ii/bar/Bar.qml:26`).
   - `Loader { active: false; sourceComponent: PanelWindow {...} }` toggled by IPC (`Cheatsheet.qml:27`).
   - Always-present `PanelWindow { visible: GlobalStates.sidebarRightOpen }` with inner `Loader { active: GlobalStates.sidebarRightOpen || Config.options.sidebar.keepRightSidebarLoaded }` (`modules/ii/sidebarRight/SidebarRight.qml`).
   Prefer destroying heavy content when closed unless open latency matters.

## Imports, singletons, qmldir

- There are **no `qmldir` files** in the tree. Quickshell exposes the config root as the module `qs`, and every subdirectory as a dotted module: `import qs` (root: `GlobalStates`, `ReloadPopup`), `import qs.services`, `import qs.modules.common`, `import qs.modules.common.widgets`, `import qs.modules.common.functions`, `import qs.modules.ii.bar`, etc. Every `.qml` in a directory is a type named after the file (PascalCase file names required).
- A file becomes a singleton with `pragma Singleton` and a `Singleton { }` root (Quickshell type). Singletons: `GlobalStates`, `modules/common/{Config,Appearance,Directories,Persistent,Icons,Images}.qml`, all of `modules/common/functions/*.qml`, `modules/common/utils/ScreenshotAction.qml`, every `services/*.qml` except `BooruResponseData.qml`, and `modules/waffle/looks/{Looks,WIcons}.qml`, plus panel-local helpers/contexts (e.g. `modules/ii/overlay/OverlayContext.qml`, `modules/ii/regionSelector/RegionFunctions.qml`, `modules/waffle/actionCenter/ActionCenterContext.qml`). This list is representative: `rg -l '^pragma Singleton'` gives the full set.
- Everything else is an instantiable component (panels, widgets, models).
- `shell.qml` uses legacy relative imports (`import "modules/common"`, `import "services"`, `import "panelFamilies"`); all other files use `qs.*`. Use `qs.*` in new code.
- Aliased import used where names collide: `import qs.modules.common.functions as CF` (`settings.qml:17`).
- JS libraries are imported by relative path, e.g. `import "shapes/material-shapes.js" as MaterialShapes` (`modules/common/widgets/MaterialShape.qml:2`).
- Most files use `pragma ComponentBehavior: Bound` (requires `required property` for delegate model data, e.g. `required property ShellScreen modelData`).

## IPC and global shortcuts

Two mechanisms, both from Quickshell:
- `IpcHandler { target: "<t>"; function f(): void {} }` → callable as `qs -c ii ipc call <t> <f> [args]`. Functions need typed signatures to be exposed (most here declare `(): void`).
- `GlobalShortcut { name: "<n>" }` → Hyprland global shortcut `quickshell:<n>`, bound in Lua as `hl.bind("SUPER + X", hl.dsp.global("quickshell:<n>"))` (see `dots/.config/hypr/hyprland/keybinds.lua`), or from shell `hyprctl dispatch 'hl.dsp.global("quickshell:lock")'` (`dots/.config/hypr/hypridle.conf:1`).

Handlers only exist while the declaring component is loaded, so most targets are family-specific. Both families register the same names for equivalent features so keybinds work in either.

### IpcHandler targets

| Target | Functions | Defined in (family) |
|---|---|---|
| `panelFamily` | `cycle()` | `shell.qml:62` (always) |
| `brightness` | `increment()`, `decrement()` | `services/Brightness.qml:248` (service) |
| `mpris` | `pauseAll()`, `playPause()`, `previous()`, `next()` | `services/MprisController.qml:170` |
| `wallpapers` | `apply(path: string)` | `services/Wallpapers.qml:173` |
| `theme` | `toggleLightDark()` | `services/MaterialThemeLoader.qml:90` |
| `cliphistService` | `update()` | `services/Cliphist.qml:150` (called from `wl-paste --watch` in `execs.lua:20-21`) |
| `lock` | `activate()`, `focus()` | `modules/common/panels/lock/LockScreen.qml:103` (both, via `Lock`/`WaffleLock`) |
| `bar` | `toggle()`, `close()`, `open()` | ii: `modules/ii/bar/Bar.qml:218`, `modules/ii/verticalBar/VerticalBar.qml:212`; waffle: `modules/waffle/bar/WaffleBar.qml:46` |
| `search` | `toggle()`, `workspacesToggle()`, `close()`, `open()`, `toggleReleaseInterrupt()`, `clipboardToggle()` | ii: `modules/ii/overview/Overview.qml:126`; waffle: `modules/waffle/taskView/WaffleTaskView.qml:79` (has `workspacesToggle`/`clipboardToggle`) **and** `modules/waffle/startMenu/WaffleStartMenu.qml:86` (lacks them) |
| `sidebarLeft` | `toggle()`, `close()`, `open()` (waffle: `toggle()` only) | ii: `modules/ii/sidebarLeft/SidebarLeft.qml:203`; waffle: `modules/waffle/actionCenter/WaffleActionCenter.qml:73` |
| `sidebarRight` | `toggle()`, `close()`, `open()` (waffle: `toggle()`) | ii: `modules/ii/sidebarRight/SidebarRight.qml:70`; waffle: `modules/waffle/notificationCenter/WaffleNotificationCenter.qml:71` |
| `mediaControls` | `toggle()`, `close()`, `open()` (waffle: `toggle()`) | ii: `modules/ii/mediaControls/MediaControls.qml:191`; waffle: `WaffleActionCenter.qml:88` |
| `session` | `toggle()`, `close()`, `open()` | ii: `modules/ii/sessionScreen/SessionScreen.qml:296`; waffle: `modules/waffle/sessionScreen/WaffleSessionScreen.qml:73` |
| `region` | `screenshot()`, `search()`, `ocr()`, `record()`, `recordWithSound()` | ii: `modules/ii/regionSelector/RegionSelector.qml:73`; waffle: `modules/waffle/screenSnip/WScreenSnip.qml:61` |
| `osdVolume` | `trigger()`, `hide()`, `toggle()` | ii: `modules/ii/onScreenDisplay/OnScreenDisplay.qml:206` |
| `osd` | `trigger()` | waffle: `modules/waffle/onScreenDisplay/WaffleOSD.qml:145` |
| `cheatsheet` | `toggle()`, `close()`, `open()` | `modules/ii/cheatsheet/Cheatsheet.qml:181` (both) |
| `osk` | `toggle()`, `close()`, `open()` | `modules/ii/onScreenKeyboard/OnScreenKeyboard.qml:130` (both) |
| `overlay` | `toggle()` | `modules/ii/overlay/Overlay.qml:78` (both) |
| `screenTranslator` | `translate()` | `modules/ii/screenTranslator/ScreenTranslator.qml:43` (both) |
| `wallpaperSelector` | `toggle()`, `random()` | `modules/ii/wallpaperSelector/WallpaperSelector.qml:73` (both) |

Hyprland also calls `qs -c $qsConfig ipc call brightness increment|decrement` (`keybinds.lua:40-42`, with `brightnessctl` fallback) and uses `qs ... ipc call TEST_ALIVE || <script>` as a "is the shell running" probe (`keybinds.lua:10,55,88,90`). `TEST_ALIVE` is not a target defined anywhere in the repo; the probe depends on how `qs ipc call` exits for an unknown target vs no running instance (unverified).

### GlobalShortcut names (`quickshell:<name>`)

| Name | Defined in | Bound in hypr? |
|---|---|---|
| `panelFamilyCycle` | `shell.qml:70` | `CTRL+SUPER+P` |
| `workspaceNumber` | `GlobalStates.qml:41` | `SUPER_L`/`SUPER_R` |
| `brightnessIncrease`, `brightnessDecrease` | `services/Brightness.qml:260,266` | no (binds use IPC) |
| `toggleLightDark` | `services/MaterialThemeLoader.qml:81` | `CTRL+SUPER+SHIFT+D` |
| `lock`, `lockFocus` | `modules/common/panels/lock/LockScreen.qml:114,123` | via `hypridle.conf` |
| `barToggle`, `barOpen`, `barClose` | ii `Bar.qml:234-252`, `VerticalBar.qml:228-246`; waffle `WaffleBar.qml:62-80` | `barToggle`: `SUPER+J` |
| `searchToggle`, `searchToggleRelease`, `searchToggleReleaseInterrupt`, `overviewClipboardToggle`, `overviewEmojiToggle` | ii `Overview.qml:149-206`; waffle `WaffleStartMenu.qml:103-145` | `searchToggleRelease`: `SUPER+SUPER_L/R`; clipboard `SUPER+V`; emoji `SUPER+Period` |
| `overviewWorkspacesToggle` | ii `Overview.qml:165`; waffle `WaffleTaskView.qml:102` | `SUPER+Tab`, also `general.lua:28,35` (gestures) |
| `overviewWorkspacesClose` | ii `Overview.qml:157` | no |
| `sidebarLeftToggle` | ii `SidebarLeft.qml:219`; waffle `WaffleActionCenter.qml:81` | `SUPER+A`, `SUPER+B`, `SUPER+O` |
| `sidebarLeftOpen`, `sidebarLeftClose`, `sidebarLeftToggleDetach` | ii `SidebarLeft.qml:228-246` | detach: `SUPER+ALT+A` |
| `sidebarRightToggle` | ii `SidebarRight.qml:86`; waffle `WaffleNotificationCenter.qml:79` | `SUPER+N` |
| `sidebarRightOpen`, `sidebarRightClose` | ii `SidebarRight.qml:94,102` | no |
| `mediaControlsToggle` | ii `MediaControls.qml:210`; waffle `WaffleActionCenter.qml:96` | `SUPER+M` |
| `mediaControlsOpen`, `mediaControlsClose` | ii `MediaControls.qml:218,226` | no |
| `sessionToggle`, `sessionOpen`, `sessionClose` | ii `SessionScreen.qml:312-330`; waffle `WaffleSessionScreen.qml:89-107` | `sessionToggle`: `CTRL+ALT+Delete` |
| `regionScreenshot`, `regionSearch`, `regionOcr`, `regionRecord`, `regionRecordWithSound` | ii `RegionSelector.qml:93-113`; waffle `WScreenSnip.qml:81-101` | `SUPER+SHIFT+S/A/X`; both `SUPER+SHIFT+R` and `SUPER+ALT+R` → `regionRecord` (`keybinds.lua:86,89`); `regionRecordWithSound` has no default bind |
| `osdVolumeTrigger`, `osdVolumeHide` | ii `OnScreenDisplay.qml:221,229` | no |
| `osdTrigger` | waffle `WaffleOSD.qml:153` | no |
| `cheatsheetToggle`, `cheatsheetOpen`, `cheatsheetClose` | `Cheatsheet.qml:197-215` | `SUPER+Slash` |
| `oskToggle`, `oskOpen`, `oskClose` | `OnScreenKeyboard.qml:146-164` | `SUPER+K` |
| `overlayToggle` | `Overlay.qml:86` | `SUPER+G` |
| `screenTranslate` | `ScreenTranslator.qml:51` | `SUPER+SHIFT+T` |
| `wallpaperSelectorToggle`, `wallpaperSelectorRandom` | `WallpaperSelector.qml:85,93` | `CTRL+SUPER+T`, `CTRL+SUPER+ALT+T` |

Regenerate this inventory after changes with `rg -n -A2 'IpcHandler \{|GlobalShortcut \{' dots/.config/quickshell/ii`.

Layer-shell namespaces: every `PanelWindow` sets `WlrLayershell.namespace: "quickshell:<name>"`; Hyprland layer rules match `quickshell:.*` (blur, ignore_alpha) and specific names (animations) in `dots/.config/hypr/hyprland/rules.lua:136-157`. Keep the prefix when adding windows.

## Multi-monitor

- Per-screen panels wrap their window in `Variants { model: Quickshell.screens; ... required property ShellScreen modelData; screen: modelData }`. Used by: ii `background/Background.qml`, `bar/Bar.qml`, `verticalBar/VerticalBar.qml`, `dock/Dock.qml`, `lock/Lock.qml`, `regionSelector/RegionSelector.qml`, `screenCorners/ScreenCorners.qml`; waffle `bar/WaffleBar.qml`, `background/WaffleBackground.qml`, `taskView/WaffleTaskView.qml`; `modules/common/widgets/FullscreenPolkitWindow.qml`; `services/Brightness.qml:197` (one brightness monitor object per screen).
- Bars filter screens by `Config.options.bar.screenList` (monitor names from `hyprctl monitors`; empty = all) (`Bar.qml:19-24`).
- Single-instance panels follow the focused monitor: `screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null` (e.g. `modules/ii/notificationPopup/NotificationPopup.qml:17`, which also reads `notifications.forceMonitor`, an undeclared key (the schema has `notifications.monitor`; see [config-and-common.md](config-and-common.md#gotchas)); `OnScreenDisplay.qml:16`, `ScreenTranslator.qml:15`).
- Panels without explicit `screen` get Quickshell's default (unverified which monitor).

## Translations

- Mark strings with `Translation.tr("English text")` (service `services/Translation.qml`). The English text is the key; `tr` returns it unchanged if no translation or while loading.
- Language: `Config.options.language.ui` (`"auto"` → `Qt.locale().name`, e.g. `de_DE`).
- Lookup order: `translations/<lang>.json` (bundled, `Quickshell.shellPath("translations")`), then `~/.config/illogical-impulse/translations/<lang>.json` (AI-generated; `generatedTranslationsDir`). A value ending in `/*keep*/` has that suffix stripped (marks an intentionally untranslated string).
- Available languages = `find <dir> -name '*.json'` over both dirs (`allAvailableLanguages`). Bundled: de_DE, en_US, es_MX, fr_FR, he_HE, id_ID, it_IT, ja_JP, pt_BR, ru_RU, tr_TR, uk_UA, vi_VN, zh_CN.
- AI generation: `scripts/ai/gemini-translate.sh <locale> [model]` (called from `welcome.qml:59` and `modules/settings/GeneralConfig.qml:16`) first runs `translations/tools/manage-translations.sh update -l en_US --yes` to refresh keys, then asks Gemini and writes into `~/.config/illogical-impulse/translations/`.
- Tools (`translations/tools/`, see its `README.md` and `guide/`): `manage-translations.sh {status|extract|update [-l xx_XX]|clean|sync}` wrapping `translation-manager.py` (regex-extracts `Translation.tr("...")`/`('...')` from `*.qml`/`*.js` under the shell dir) and `translation-cleaner.py`. The wrapper derives paths from its own location; the README's example paths (`.config/quickshell/translations/tools`) and the Python defaults (`--translations-dir .config/quickshell/translations`) are stale, so prefer the wrapper.
- Only literal strings are extractable. `Translation.tr(someVar)` works at runtime but the key must be added manually.

## scripts/ overview

Python scripts run in the uv venv at `$ILLOGICAL_IMPULSE_VIRTUAL_ENV` (default `~/.local/state/quickshell/.venv`, set in `dots/.config/hypr/hyprland/env.lua:16`). Python files use a shebang that sources the venv (`scripts/colors/generate_colors_material.py:1`); others have `*-venv.sh` wrappers that `source $ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/activate`.

| Dir | Contents / caller |
|---|---|
| `colors/` | `switchwall.sh` (wallpaper + theme pipeline: matugen, `generate_colors_material.py`, `applycolor.sh`, kde-material-you-colors, `code/material-code-set-color.sh`, optional `../ai/gemini-categorize-wallpaper.sh`, `scheme_for_image.py`). Path in `Directories.wallpaperSwitchScriptPath`. `random/` (konachan/osu random wallpaper, used by `welcome.qml`, `services/LauncherSearch.qml`, `modules/settings/QuickConfig.qml`), `terminal/` (terminal scheme templates). Output colors land in `~/.local/state/quickshell/user/generated/colors.json`, read by `services/MaterialThemeLoader.qml`. Theming pipeline: [../dotfiles-and-theming.md](../dotfiles-and-theming.md). |
| `images/` | `find_regions.py` (region selector, `modules/ii/regionSelector/RegionSelection.qml`), `least_busy_region.py` (background widget placement, `modules/ii/background/widgets/AbstractBackgroundWidget.qml`), `text_color.py` (screen translator overlay). Each via `*-venv.sh`. |
| `thumbnails/` | `thumbgen.py` via `thumbgen-venv.sh`, or `generate-thumbnails-magick.sh` (ImageMagick) — freedesktop thumbnails for `services/Wallpapers.qml`. |
| `keyring/` | `try_lookup.sh` (`services/KeyringStorage.qml`), `unlock.sh` (`LockScreen.qml`, unlocks the keyring with the lock password), `is_unlocked.sh` (used by the other two). |
| `ai/` | `gemini-translate.sh` (above), `gemini-categorize-wallpaper.sh` (switchwall). |
| `t3/` | `t3-sidebar-bridge.mjs` (Node; run by `services/T3.qml`, see [t3-sidebar.md](t3-sidebar.md)). |
| `hyprland/hyprconfigurator.py` | Reads/writes Hyprland options for `services/HyprlandConfig.qml`. |
| `videos/record.sh` | Screen recording (`Directories.recordScriptPath`; also bound directly in `keybinds.lua:88-92`). |
| `musicRecognition/recognize-music.sh` | `services/SongRec.qml`. |
| `cava/raw_output_config.txt` | cava config for the visualizer in `modules/ii/mediaControls/MediaControls.qml`. |

Also `services/gCloud/token-from-key-venv.sh` lives under services.

## Runtime dependencies

- **Quickshell**: git build pinned by commit in `sdata/dist-arch/illogical-impulse-quickshell-git/PKGBUILD:1` (`_commit=...`, pkgver `0.1.0.r1`). The config relies on post-0.1 git features (e.g. `Quickshell.shellPath`, `LazyLoader`, `JsonAdapter`/`JsonObject`, `GlobalShortcut`, `IpcHandler`, `ShapeCanvas` from the shapes lib). An ALPM hook runs `quickshell --private-check-compat` after Qt upgrades (`quickshell-check.hook`). Other distros: see [../distros.md](../distros.md).
- **Qt 6 modules** (PKGBUILD deps): qt6-base, qt6-declarative, qt6-svg, qt6-5compat (`Qt5Compat.GraphicalEffects`), qt6-imageformats, qt6-avif-image-plugin, qt6-multimedia, qt6-positioning, qt6-quicktimeline, qt6-sensors, qt6-tools, qt6-translations, qt6-virtualkeyboard, qt6-wayland; KDE: kirigami (`AppIcon.qml` uses `Kirigami.Icon`), syntax-highlighting, kdialog. `Qt.labs.synchronizer` is imported (e.g. `Cheatsheet.qml`).
- **Python venv**: packages in `sdata/uv/requirements.in` (locked in `requirements.txt`; regenerate with `uv pip compile requirements.in -o requirements.txt`), installed by `install-python-packages` (`sdata/lib/package-installers.sh`, invoked from `sdata/subcmd-install/2.setups.sh`). See `sdata/uv/README.md`.
- **External CLIs** called from QML/scripts: hyprctl, matugen, cliphist/wl-paste, brightnessctl, ydotool, jq, curl, ImageMagick, songrec etc. Full list: [../setup-and-install.md](../setup-and-install.md).
- Fonts referenced by default config: Google Sans Flex, JetBrains Mono NF, Readex Pro, Space Grotesk, Material Symbols Rounded.
- `./diagnose` (repo root) prints quickshell/qt6-base versions and checks the venv (`diagnose:58-95`).

## Recipe: add a new panel end-to-end (ii family)

1. **State flag** (if other panels/keys need it): add `property bool fooOpen: false` to `GlobalStates.qml`.
2. **Panel file**: create `modules/ii/foo/Foo.qml` with a `Scope` root:
   ```qml
   import qs
   import qs.services
   import qs.modules.common
   import qs.modules.common.widgets
   import QtQuick
   import Quickshell
   import Quickshell.Io
   import Quickshell.Wayland
   import Quickshell.Hyprland
   Scope {
       id: root
       LazyLoader {
           active: GlobalStates.fooOpen
           component: PanelWindow {
               screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
               WlrLayershell.namespace: "quickshell:foo"
               color: "transparent"
               anchors { top: true }
               implicitWidth: 400; implicitHeight: 200
               // content: use Appearance tokens + common widgets
           }
       }
       IpcHandler { target: "foo"; function toggle(): void { GlobalStates.fooOpen = !GlobalStates.fooOpen } }
       GlobalShortcut { name: "fooToggle"; description: "Toggles foo"; onPressed: GlobalStates.fooOpen = !GlobalStates.fooOpen }
   }
   ```
   Per-monitor instead: wrap in `Variants { model: Quickshell.screens }` with `required property ShellScreen modelData`. For click-outside-to-close, follow `SidebarRight.qml` (`GlobalFocusGrab.addDismissable(window)` + `Connections { target: GlobalFocusGrab; function onDismissed() {...} }`). Keyboard: `WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None`.
3. **Register** in `panelFamilies/IllogicalImpulseFamily.qml`: `import qs.modules.ii.foo` and `PanelLoader { component: Foo {} }` (add `extraCondition: Config.options.foo.enable` if optional). For waffle either write a waffle variant or add the ii one under "Fallbacks" in `WaffleFamily.qml`.
4. **Config options** (optional): add a `JsonObject` in `modules/common/Config.qml` (see [config-and-common.md](config-and-common.md#adding-a-new-config-option)) and UI in `modules/settings/*` ([settings-app.md](settings-app.md)).
5. **Strings**: wrap with `Translation.tr()`, then `translations/tools/manage-translations.sh update` to add keys.
6. **Keybind**: `hl.bind("SUPER + X", hl.dsp.global("quickshell:fooToggle"), { description = "Shell: Toggle foo" })` in `dots/.config/hypr/hyprland/keybinds.lua` ([../hyprland.md](../hyprland.md)). The `description` appears in the cheatsheet (via `services/HyprlandKeybinds.qml`; unverified exact parsing).
7. **Layer rule** (optional animation/blur) in `dots/.config/hypr/hyprland/rules.lua` matching `quickshell:foo`.
8. Test: `qs -c ii ipc call foo toggle`.

A new **module inside an existing panel** (e.g. a bar widget) is just a component file in that panel's folder referenced from its layout; see [panels-ii.md](panels-ii.md) / [panels-waffle.md](panels-waffle.md). A new **service** goes in `services/` as a singleton; see [services.md](services.md).

## Debugging and reloading

- **Run in foreground**: `qs -c ii` (or fish `q`) in a terminal prints QML warnings/`console.log` output. Kill the running instance first (`killall qs quickshell`, as the `CTRL+SUPER+R` bind does).
- **Logs of a running instance**: Quickshell CLI `qs log -c ii` (unverified exact flags; check `qs --help`/`qs log --help`).
- **Hot reload**: Quickshell watches the config's QML files and reloads the shell on save; `ReloadPopup.qml` then shows "Quickshell reloaded" or "Reload failed" + error text (the error popup stays 10 s). A failed reload keeps the previous working shell. Singleton/`Config` state is rebuilt on reload (unverified whether singletons persist across reload; `GlobalStates` flags reset to defaults in practice since they are plain properties). Standalone `qs -p` apps (settings, welcome) reload independently.
- **Manual reload**: right sidebar button "Reload Hyprland & Quickshell" runs `hyprctl reload` + `Quickshell.reload(true)` (`modules/ii/sidebarRight/SidebarRightContent.qml:270-272`).
- **Config changes** don't need a reload: `config.json` is watched (`Config.qml` `FileView.watchChanges`).
- **Exercise IPC**: `qs -c ii ipc show` lists targets (Quickshell CLI; unverified), `qs -c ii ipc call <target> <fn>`.
- **Theme**: re-read colors with `MaterialThemeLoader.reapplyTheme()` (called at startup) or rerun `scripts/colors/switchwall.sh`.
- **Reset first run**: delete `~/.local/state/quickshell/user/first_run.txt` (or `./setup resetfirstrun`, `sdata/subcmd-resetfirstrun`).

## Gotchas

- Everything gated on `Config.ready`: panels do not exist until `config.json` loads. A JSON syntax error in the user config leaves `ready` false (unverified: FileView behaviour on parse error) → empty desktop.
- In the waffle family two components (`WaffleTaskView`, `WaffleStartMenu`) both declare `IpcHandler { target: "search" }` (overlapping IPC target/methods; their GlobalShortcut names are distinct). Which handler receives an IPC call is unverified.
- `ii`-only shortcuts (`sidebarLeftOpen`, `overviewWorkspacesClose`, `osdVolume*`, ...) silently do nothing under waffle.
- `bar` target is defined by both `Bar` and `VerticalBar`, but only one is loaded at a time (`bar.vertical`).
- `qsConfig` env var (`variables.lua:5`) is the config folder name used by Hyprland binds/execs; QML code never hardcodes the folder and resolves its own files with `Quickshell.shellPath(...)`. The fish alias `q` and `modules/waffle/README.md` hardcode `ii`. Renaming the folder means changing `qsConfig` and those.
- The `modules/common/widgets/shapes` git submodule must be initialised (`git submodule update --init`); otherwise `MaterialShape`/`MaterialCookie` imports fail and dependent panels break at load.
- `Directories.qml` `Component.onCompleted` deletes and recreates cache dirs (cover art, cliphist decode, `/tmp/quickshell/media/images`) on every start, including `qs -p` apps.
