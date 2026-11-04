# Quickshell shell: config and `modules/common`

Scope: `dots/.config/quickshell/ii/modules/common/**` (shared singletons, helpers, models, the lock-screen base, the widget library) and `defaults/`. For the overall structure, entry points and IPC see [architecture.md](architecture.md). Services: [services.md](services.md). Settings UI that edits config: [settings-app.md](settings-app.md).

Paths are relative to `dots/.config/quickshell/ii/` unless noted. Import with `import qs.modules.common` (singletons + subfolders are separate modules: `qs.modules.common.widgets`, `.functions`, `.models`, `.utils`, `.panels.lock`).

## Key files

| File | Kind | Role |
|---|---|---|
| `modules/common/Config.qml` | singleton | User options schema + persistence (`~/.config/illogical-impulse/config.json`). |
| `modules/common/Appearance.qml` | singleton | Material 3 colors, derived layer colors, transparency, rounding, fonts, animation curves, sizes. |
| `modules/common/Directories.qml` | singleton | All filesystem paths; creates/cleans dirs on start. |
| `modules/common/Persistent.qml` | singleton | Runtime state persisted across restarts (`~/.local/state/quickshell/states.json`). |
| `modules/common/Icons.qml` | singleton | Icon-name helpers (battery, bluetooth, network, ...). Partly from caelestia (GPLv3). |
| `modules/common/Images.qml` | singleton | Valid image extensions, freedesktop thumbnail size names. |
| `modules/common/functions/` | singletons | Pure helpers (colors, strings, files, dates, fuzzy search, session actions). |
| `modules/common/models/` | components | Non-visual data objects (quick toggles, workspaces, launcher results, gCloud, Hyprland options). |
| `modules/common/utils/` | components (+1 singleton) | Process wrappers (screenshots, downloads, multi-step commands). |
| `modules/common/panels/lock/` | components | `LockScreen` base shared by ii `Lock` and waffle `WaffleLock`. |
| `modules/common/widgets/` | components | Reusable Material-style widget library (~120 files) + `shapes` git submodule + `widgetCanvas/`. |
| `defaults/ai/prompts/*.md` | data | Bundled AI system prompts. |

## Config.qml (critical)

### Storage and lifecycle (`modules/common/Config.qml:8-76`)
- File: `Directories.shellConfigPath` = `~/.config/illogical-impulse/config.json` (`Directories.qml:34-36`; dir created by `Directories` on start).
- `FileView { path; watchChanges: true; blockWrites: root.blockWrites }` with a `JsonAdapter` (`id: configOptionsJsonAdapter`) exposed as `Config.options` (`property alias options`).
- `onLoaded` → `Config.ready = true`. Panels and many services wait on `Config.ready` (e.g. `panelFamilies/PanelLoader.qml`).
- `onLoadFailed` with `FileNotFound` → `writeAdapter()`: a full default config is written on first run.
- External edits: `onFileChanged` → `fileReloadTimer` (`readWriteDelay`, default 50 ms) → `reload()`. Changes made by hand, by the settings app (separate `qs -p` process), or by scripts take effect live in the main shell.
- In-shell writes: assigning any property under `Config.options` triggers `onAdapterUpdated` → `fileWriteTimer` (50 ms debounce) → `writeAdapter()`, which rewrites the whole JSON file from the adapter.
- Knobs: `Config.readWriteDelay` (settings/welcome/killDialog set 0), `Config.blockWrites` (killDialog sets true so it never rewrites the user file).
- Keys missing from a user's file keep their QML defaults. Unverified: whether unknown keys in the file survive a `writeAdapter()` (assume they are dropped).

### Reading and writing
- Read: bind directly: `visible: Config.options.dock.enable`. Bindings are reactive to file reloads. Many call sites use `Config.options?.x` / `Config?.options.x ?? fallback` for safety during early init; this is harmless, so copy the style of the surrounding file.
- Write: assign: `Config.options.bar.vertical = true`. The settings pages do `checked: Config.options.a.b; onCheckedChanged: Config.options.a.b = checked` (e.g. `modules/settings/BarConfig.qml:13-19`).
- String paths: `Config.setNestedValue("bar.vertical", "true")` (`Config.qml:16-44`): splits on `.`, creates missing intermediate objects, and converts `"true"/"false"`/numeric strings with `JSON.parse`. Used by the AI tool `set_shell_config` (`services/Ai.qml:821`).
- From outside the shell: edit `config.json` (e.g. `jq`); scripts like `scripts/colors/switchwall.sh` read it with `jq`. There is no IPC target for setting config.

### Schema (top-level keys of `Config.options`)
Types used: `bool`, `int`, `real`, `string`, `list<string>`, `list<var>`, nested `JsonObject`. Comments next to properties document allowed values; read the file for exact defaults.

| Key | Line | Contents (selection) |
|---|---|---|
| `panelFamily` | 81 | `"ii"` or `"waffle"` (see [architecture.md](architecture.md#panel-families)). |
| `policies` | 83 | `weeb` (0 no / 1 open / 2 closet) — gates wallpaper-selector and settings features. |
| `appearance` | 87 | `extraBackgroundTint`, `fakeScreenRounding`, `fonts.{main,numbers,title,iconNerd,monospace,reading,expressive}`, `transparency.{enable,automatic,backgroundTransparency,contentTransparency}`, `wallpaperTheming.*` (+`terminalGenerationProps`), `palette.{type,accentColor}`. |
| `audio` | 122 | `protection.{enable,maxAllowedIncrease,maxAllowed}`. |
| `apps` | 132 | Commands for bluetooth/network/user/taskManager/terminal/update/volumeMixer. |
| `background` | 144 | `widgets.{clock,weather}`, `parallax`, `wallpaperPath`, `thumbnailPath`, ... |
| `bar` | 206 | `autoHide`, `bottom`, `cornerStyle` (0 hug/1 float/2 rect), `vertical`, `screenList`, `resources`, `utilButtons`, `workspaces`, `weather`, `indicators`, `tooltips`, `topLeftIcon`, ... |
| `battery`, `calendar`, `cheatsheet`, `conflictKiller`, `crosshair`, `dock` | 267–305 | Per-feature options (`dock.enable` gates the Dock panel). |
| `interactions` | 317 | `scrolling.*`, `deadPixelWorkaround`. |
| `language` | 329 | `ui` (`"auto"` or `xx_XX`). |
| `launcher`, `light` (`night`, `antiFlashbang`), `lock` (`blur`, `security`, `launchOnStartup`...), `media`, `networking` (`userAgent`), `notifications` (`timeout`, `monitor.{enable,name}`), `osd`, `osk`, `overlay`, `overview` | 333–402 | |
| `regionSelector`, `resources`, `tray`, `musicRecognition`, `search` (`prefix.*`, `imageSearch`) | 412–452 | |
| `sidebar` | 473 | `t3.tokenFile`, `t3.remotes` (see [t3-sidebar.md](t3-sidebar.md)), `cornerOpen`, `quickToggles` (`android.toggles` list), `quickSliders`, `keepRightSidebarLoaded`, ... |
| `screenRecord`, `screenSnip`, `sounds`, `time` (`pomodoro`), `updates`, `wallpaperSelector`, `windows` (`showTitlebar`, `centerTitle`), `hacks`, `workSafety` | 513–562 | |
| `waffles` | 574 | Waffle-family-only: `tweaks.*`, `bar.{bottom,leftAlignApps}`, `actionCenter.toggles`, `calendar`. |

Do not confuse with `Persistent.states` (runtime state, not user preferences) or `GlobalStates` (in-memory UI flags).

### Adding a new config option
1. Pick the section in `Config.qml` (or add `property JsonObject foo: JsonObject { ... }` inside the `JsonAdapter`). Keep camelCase names; the property name **is** the JSON key.
2. Declare with an explicit type and default, plus a comment for enums/units:
   `property bool showSeconds: false // Show seconds in bar clock`
   Lists: `property list<string> things: ["a", "b"]`; arbitrary objects: `property list<var>`. Use `real` for anything fractional (`int` truncates).
3. Read it where needed: `Config.options.time.showSeconds`. If code can run before load, guard with `Config.ready` or `?.`.
4. Expose it in the settings app (optional): add a `ConfigSwitch` / `ConfigSpinBox` / `ConfigSlider` / `ConfigSelectionArray` in the right `modules/settings/*Config.qml` page bound as shown above, with `Translation.tr()` labels. See [settings-app.md](settings-app.md).
5. Existing users get the default automatically (missing key → QML default), and the key is written into their file on the next write.
6. Renaming/removing an option: there is no migration code (unverified: none found in `Config.qml`); old keys in user files become dead. Grep all usages (`rg 'Config.options(\?)?\.section\.name'`) including `scripts/` (jq reads in `switchwall.sh`) and `modules/settings/`.
7. Run `translations/tools/manage-translations.sh update` if you added labels.

## Appearance.qml

Singleton (`modules/common/Appearance.qml`). Groups:

- **`m3colors`** (`:37-109`): 53 Material 3 roles `m3background, m3onBackground, m3surface*, m3surfaceContainer{Lowest,Low,,High,Highest}, m3primary/onPrimary/primaryContainer/..., m3secondary*, m3tertiary*, m3error*, m3*Fixed*, m3outline(Variant), m3shadow, m3scrim, m3inverse*, m3success*` plus `term0..term15` and `darkmode`, `transparent`. Values in the file are fallbacks; `services/MaterialThemeLoader.qml:22-33` overwrites them from `~/.local/state/quickshell/user/generated/colors.json` by converting each `snake_case` key to `m3CamelCase`, then sets `darkmode` from background lightness. A new role needs a property here and the key in the generator output.
- **`colors`** (`:111-198`): semantic tokens built from m3colors with `ColorUtils.mix/transparentize/solveOverlayColor`. Surface stack: `colLayer0` (window background) → `colLayer1` (cards) → `colLayer2` → `colLayer3` → `colLayer4`, each with `colOnLayerN`, `colLayerNHover`, `colLayerNActive` (and some `Disabled`/`Base`/`Border`). Accents: `colPrimary/Secondary/Tertiary/Error` with `Hover/Active`, `*Container` variants, `colOn*`. Misc: `colSubtext`, `colTooltip/colOnTooltip`, `colScrim`, `colShadow`, `colOutline(Variant)`, `colSurfaceContainer*`. **Use these in widgets instead of raw m3 colors** so transparency works.
- **Transparency** (`:18-35`): `backgroundTransparency` / `contentTransparency` from `Config.options.appearance.transparency`; "automatic" derives background transparency from wallpaper vibrancy via a 1-color `ColorQuantizer` on the wallpaper (or its thumbnail for videos).
- **`rounding`** (`:201-211`): `unsharpen 2, unsharpenmore 6, verysmall 8, small 12, normal 17, large 23, verylarge 30, full 9999, screenRounding (=large), windowRounding 18`.
- **`font`** (`:214-250`): `family.{main,numbers,title,iconMaterial ("Material Symbols Rounded"),iconNerd,monospace,reading,expressive}` (mostly from `Config.options.appearance.fonts`), `variableAxes.{main,numbers,title}`, `pixelSize.{smallest 10, smaller 12, smallie 13, small 15, normal 16, large 17, larger 19, huge 22, hugeass 23, title}`.
- **`animationCurves`**: bezier lists (M3 expressive `expressiveFastSpatial/DefaultSpatial/SlowSpatial/Effects` with durations 350/500/650/200 ms, `emphasized*`, `standard*`).
- **`animation`**: presets `elementMove`, `elementMoveSmall`, `elementMoveEnter`, `elementMoveExit`, `elementMoveFast`, `elementResize`, `clickBounce`, `scroll`, `menuDecel`; each has `duration`, `type`, `bezierCurve`, `velocity` and usually a `numberAnimation` (some `colorAnimation`) `Component`. Pattern: `Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }` (`modules/ii/dock/Dock.qml:62`), or set `duration/easing.type/easing.bezierCurve` from a preset manually.
- **`sizes`**: bar heights/widths (`barHeight` depends on `bar.cornerStyle`), `sidebarWidth 460`, `sidebarWidthExtended 750`, `elevationMargin 10`, `hyprlandGapsOut 5`, `notificationPopupWidth`, `osdWidth`, `searchWidth`, `mediaControls*`, `wallpaperSelector*`, `verticalBarWidth`.
- `syntaxHighlightingTheme`: `"Monokai"` dark / `"ayu Light"` light.

The waffle family uses its own `modules/waffle/looks/Looks.qml` instead (see [panels-waffle.md](panels-waffle.md)).

## Directories.qml

All `readonly`/plain string properties (`modules/common/Directories.qml`).
- XDG (with `file://`): `home, config, state, cache, genericCache, documents, downloads, pictures, music, videos` from Qt `StandardPaths`. `state` and `cache` are app-scoped: they resolve to `~/.local/state/quickshell` and `~/.cache/quickshell` (consistent with matugen's output path `~/.local/state/quickshell/user/generated/colors.json` in `dots/.config/matugen/config.toml:6`). `config` is `~/.config`.
- Shell paths (no `file://`): `assetsPath`, `scriptPath` (via `Quickshell.shellPath`), `shellConfig` = `~/.config/illogical-impulse`, `shellConfigName` = `config.json`, `shellConfigPath`, `userActions` (`~/.config/illogical-impulse/actions`).
- State: `todoPath` (`state/user/todo.json`), `notesPath` (`state/user/notes.txt`), `generatedMaterialThemePath` (`state/user/generated/colors.json`), `generatedWallpaperCategoryPath`.
- Cache/temp: `favicons`, `coverArt`, `conflictCachePath`, `notificationsPath` (`cache/notifications/notifications.json`), `tempImages` (`/tmp/quickshell/media/images`), `cliphistDecode`, `screenshotTemp`.
- Other: `wallpaperSwitchScriptPath`, `aiTranslationScriptPath`, `recordScriptPath`, user avatar candidates (AccountsService, `~/.face`, `~/.face.icon`).
- `Component.onCompleted` (`:48-58`) runs `mkdir -p` for shellConfig/favicons/userActions and **wipes** coverArt, cliphistDecode and tempImages on every startup.
- Use `FileUtils.trimFileProtocol()` when passing XDG paths to processes. Add new paths here rather than hardcoding.

## Persistent.qml

- File: `${Directories.state}/states.json` → `~/.local/state/quickshell/states.json`. Same FileView+JsonAdapter pattern as Config (100 ms debounce, `watchChanges`, creates the file if missing). Access via `Persistent.states.*`, check `Persistent.ready`.
- Keys: `hyprlandInstanceSignature`, `cheatsheet.tabIndex`, `sidebar.bottomGroup.{collapsed,tab}`, `idle.inhibit`, `overlay.open` (list) and per-overlay-widget geometry `{pinned,clickthrough,x,y,width,height[,tabIndex]}` for crosshair/floatingImage/fpsLimiter/recorder/resources/volumeMixer/notes, `timer.pomodoro.*`, `timer.stopwatch.*`.
- `isNewHyprlandInstance` (`:16`): compares the stored signature with `$HYPRLAND_INSTANCE_SIGNATURE` on load; used to restore state only within one Hyprland session (`services/Idle.qml:19`) and to auto-lock on login (`LockScreen.qml:135`).
- Use for UI state that should survive a shell restart but isn't a user preference (tab indexes, window positions).

## Icons.qml / Images.qml
- `Icons`: `getBatteryIcon(percentage)`, `getBluetoothDeviceMaterialSymbol(systemIconName)`, `getNetworkMaterialSymbol()` etc. → Material Symbols names.
- `Images`: `validImageTypes`, `validImageExtensions`, `isValidImageByName(name)`, `thumbnailSizes` (`normal 128, large 256, x-large 512, xx-large 1024`), `thumbnailSizeNameForDimensions(w, h)`.

## functions/ (all singletons, `import qs.modules.common.functions`)

| File | Functions |
|---|---|
| `ColorUtils.qml` | `mix(c1,c2,p)`, `transparentize(c,p)`, `applyAlpha`, `isDark`, `colorWithHueOf`, `colorWithSaturationOf`, `colorWithLightness(Of)`, `adaptToAccent`, `clamp01`, `solveOverlayColor(base,target,opacity)` (inverse alpha blend used for transparent layers). |
| `StringUtils.qml` | `format(str, ...args)`, `getDomain`, `getBaseUrl`, `shellSingleQuoteEscape` (use for every string interpolated into `bash -c`), `splitMarkdownBlocks`, `escapeBackslashes`, `wordWrap`, `cleanMusicTitle`, `friendlyTimeForSeconds`, `escapeHtml`, `cleanCliphistEntry`, `stringListContainsSubstring`, `cleanPrefix`, `cleanOnePrefix`, `toTitleCase`. |
| `FileUtils.qml` | `trimFileProtocol`, `fileNameForPath`, `folderNameForPath`, `trimFileExt`, `parentDirectory`. |
| `DateUtils.qml` | `getFirstDayOfWeek`, `sameDate`, `getIthDayDateOfSameWeek`. |
| `NumberUtils.qml` | `roundToEven`. |
| `ObjectUtils.qml` | `toPlainObject(qtObj)`, `applyToQtObject(qtObj, json)`. |
| `NotificationUtils.qml` | `findSuitableMaterialSymbol(summary)`, `getFriendlyNotifTimeString(ts)`. |
| `Session.qml` | `closeAllWindows`, `changePassword`, `lock`, `suspend`, `logout`, `launchTaskManager`, `hibernate`, `poweroff`, `reboot`, `rebootToFirmware`. |
| `Fuzzy.qml` / `fuzzysort.js` | `go`, `prepare` wrappers over fuzzysort. |
| `Levendist.qml` / `levendist.js` | `computeScore`, `computeTextMatchScore` (Levenshtein). |

## models/

| File | Purpose |
|---|---|
| `NestableObject.qml` | `QtObject` that allows children to be declared inside (base for other models). |
| `AdaptedMaterialScheme.qml` | Partial layer colors adapted to a given `required color` (e.g. album-art tinted media controls). |
| `AnimatedTabIndexPair.qml` | Two indices animating at different speeds for tab indicators. |
| `IndexModel.qml` | `ScriptModel` of `0..count-1`. |
| `FolderListModelWithHistory.qml` | Folder model with back/up navigation history (wallpaper selector / file pickers). |
| `LauncherSearchResult.qml` | Launcher result object (`type`, `name`, icon type enum, actions...). |
| `WorkspaceModel.qml` | Per-monitor workspace occupancy/active state from Hyprland. |
| `quickToggles/*Toggle.qml` + `QuickToggleModel.qml` | One model per quick toggle (network, bluetooth, darkMode, nightLight, mic, gameMode, ...); base defines name/state/actions. Used by ii sidebarRight and waffle actionCenter toggle lists (`Config.options.sidebar.quickToggles.android.toggles`, `waffles.actionCenter.toggles`). |
| `hyprland/HyprlandConfigOption.qml` | `required key`; `fetch()`/`setValue()` a Hyprland option (via `services/HyprlandConfig.qml`). |
| `gCloud/GCloudApi.qml`, `GCloudTranslate.qml`, `GCloudVision.qml`, `GCloudVisionResult.qml` | Google Cloud API request objects. |

## utils/

| File | Purpose |
|---|---|
| `ScreenshotAction.qml` (singleton) | `getCommand(x, y, w, h, path, action, saveDir)` builds the shell command for region actions (copy/save/search/OCR/record). |
| `TempScreenshotProcess.qml` | `Process` that `grim`s a `required screen` into `Directories.screenshotTemp`. |
| `ImageDownloaderProcess.qml` | `Process` downloading `sourceUrl` → `filePath` with configured user agent; `signal done(path, width, height)`. |
| `MultiTurnProcess.qml` | Runs a sequence of commands/functions (`runSequence(seq)`). |

## panels/lock/

`LockScreen.qml` is the family-agnostic lock: wraps `WlSessionLock`, takes `required property Component lockSurface` (each family supplies its UI: `modules/ii/lock/Lock.qml:11`, `modules/waffle/lock/WaffleLock.qml:19`), shares state via `LockContext.qml` (password buffer, PAM auth; `pam/fprintd.conf` for fingerprint), unlocks the keyring via `scripts/keyring/unlock.sh`, owns IPC `lock` and shortcuts `lock`/`lockFocus`, and auto-locks on startup if `Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance`.

## widgets/ catalogue (`import qs.modules.common.widgets`)

Material 3 styled, themed via `Appearance`. Grouped by purpose:

**Text & icons**
- `StyledText` — `Text` with main/numbers font auto-pick, `Appearance` size/color, optional `animateChange` slide/fade.
- `MaterialSymbol` — Material Symbols Rounded glyph (`text` = icon name, `iconSize`, `fill` 0–1).
- `OptionalMaterialSymbol` — loader that only shows a `MaterialSymbol` when `icon` is non-empty.
- `CustomIcon` — SVG from `assets/icons` (`source`, `colorize`, `color`).
- `AppIcon` — `Kirigami.Icon` for app icons. `Favicon` — website favicon. `DirectoryIcon` — folder/file icon (from caelestia).
- `MaterialShapeWrappedMaterialSymbol` — symbol inside a Material shape. `SqueezedAnnotationStyledText` — Lens-style text annotation.
- `KeyboardKey` — keycap label (cheatsheet).

**Buttons**
- `RippleButton` — base button: ripple, hover/toggled colors (`colBackground*`, `colRipple*`), `buttonRadius`, `toggled`, `downAction/releaseAction/altAction/middleClickAction`.
- `RippleButtonWithIcon`, `DialogButton`, `MenuButton`, `FloatingActionButton`, `NotificationActionButton`, `LightDarkPreferenceButton`.
- `GroupButton` / `SelectionGroupButton` with containers `ButtonGroup`, `VerticalButtonGroup`, `FlowButtonGroup` — M3 connected button groups.
- `ButtonMouseArea`, `PointingHandInteraction`, `PointingHandLinkHover` — mouse areas with button/cursor defaults.

**Toolbars & navigation**
- `Toolbar`, `ToolbarButton`, `IconToolbarButton`, `IconAndTextToolbarButton`, `VibrantToolbarButton`, `ToolbarPairedFab`, `ToolbarTabBar`, `ToolbarTabButton`, `ToolbarTextField` — M3 floating toolbar set.
- `NavigationRail`, `NavigationRailButton`, `NavigationRailExpandButton`, `NavigationRailTabArray` — side rail (settings app).
- `SecondaryTabBar`, `SecondaryTabButton` — tab bars. `AddressBar`, `AddressBreadcrumb` — path bar (wallpaper selector).

**Inputs**
- `StyledSwitch`, `StyledSlider`, `StyledSpinBox`, `StyledRadioButton`, `StyledComboBox`, `StyledTextInput`, `StyledTextArea`, `MaterialTextField`, `MaterialTextArea`.

**Settings-page building blocks** (used by `modules/settings/*`)
- `ContentPage` (scrollable page), `ContentSection` (`title`, `icon`, default content), `ContentSubsection`, `ContentSubsectionLabel`.
- `ConfigRow`, `ConfigSwitch` (`buttonIcon`, `text`, `checked`), `ConfigSpinBox`, `ConfigSlider`, `ConfigSelectionArray` (`options: [{displayName, icon, value}]`, `currentValue`, `signal selected(newValue)`).
- `NoticeBox` (`materialIcon`, `text`).

**Dialogs, menus, tooltips**
- `WindowDialog`, `WindowDialogTitle`, `WindowDialogParagraph`, `WindowDialogSectionHeader`, `WindowDialogSeparator`, `WindowDialogSlider`, `WindowDialogButtonRow`, `DialogListItem` — M3 dialog pieces.
- `SelectionDialog` (`titleText`, `items`, `defaultChoice`).
- `StyledToolTip`, `StyledToolTipContent`, `PopupToolTip` (popup-window tooltip for bars).
- `FullscreenPolkitWindow` — per-screen polkit prompt window (Variants over screens).

**Lists, scrolling, layout**
- `StyledListView`, `StyledFlickable` (accumulated smooth wheel scrolling), `StyledScrollBar`, `ScrollEdgeFade`, `FocusedScrollMouseArea`.
- `Box`, `BoxLayout` (row-or-column), `Revealer` (`reveal`, `vertical`: animated show/hide by size), `FadeLoader` (`shown`, opacity-animated Loader), `PagePlaceholder`.
- `CalendarView`, `WeekRow` — calendar grid.

**Progress & indicators**
- `StyledProgressBar`, `StyledIndeterminateProgressBar`, `ClippedProgressBar`, `CircularProgress`, `ClippedFilledCircularProgress`, `MaterialLoadingIndicator`, `WavyLine`, `WaveVisualizer` (cava bars), `Graph` (resource history).

**Surfaces & effects**
- `StyledRectangle` (`contentLayer` enum: Background/Pane/Group/Subgroup/Control), `Pill`, `Circle`, `RoundCorner` (fake screen corners), `DashedBorder`.
- `StateLayer`, `StateOverlay` (`hover/press/drag` M3 state layers).
- `StyledDropShadow`, `StyledRectangularShadow`, `StyledBlurEffect`, `Colorizer`, `MaskMultiEffect`.
- `StyledImage`, `ThumbnailImage` (freedesktop thumbnails), `CliphistImage` (decoded clipboard image).
- `MaterialShape` (M3 expressive shapes via `ShapeCanvas`), `MaterialCookie`, `SineCookie` (cookie-shaped clocks/avatars).
- `ErrorShakeAnimation`.

**Notifications**: `NotificationListView`, `NotificationGroup`, `NotificationItem`, `NotificationAppIcon`, `NotificationGroupExpandButton` (shared by sidebar and popups).

**Interaction helpers**: `DragManager` (drag-region MouseArea, used by region selector), `widgetCanvas/{WidgetCanvas, AbstractWidget, AbstractOverlayWidget}` — draggable widget placement for background widgets and the overlay.

**`shapes/` (git submodule)**: `https://github.com/end-4/rounded-polygon-qmljs.git` (`.gitmodules`), a JS port of Material rounded polygons. Imported as `import qs.modules.common.widgets.shapes` (provides `ShapeCanvas`) plus JS files (`shapes/material-shapes.js`, `shapes/geometry/offset.js`, `shapes/shapes/corner-rounding.js`). In a fresh clone without `git submodule update --init` the folder is empty and `MaterialShape`/`MaterialCookie` (and everything using them, e.g. `NotificationAppIcon`) fail to load.

## Conventions for new widgets

- File name = type name, PascalCase, in `modules/common/widgets/` only if reused by more than one panel or family; otherwise keep it next to its panel. Waffle-specific widgets go in `modules/waffle/looks/` with a `W` prefix.
- Prefix `Styled*` = themed wrapper around a Qt Quick / Controls type; `Config*` = settings-row control; `Material*` = M3-specific visual.
- Base on existing widgets (`RippleButton`, `StyledText`, `MaterialSymbol`) instead of raw `Button`/`Text` so fonts, colors, ripples and cursor stay consistent.
- Colors: `Appearance.colors.colLayerN` / `colOnLayerN` matching the nesting level, `colPrimary`/`colOnPrimary` for accents, `*Hover`/`*Active` for states. Avoid hardcoded hex (only `ReloadPopup.qml` does, deliberately).
- Sizes: `Appearance.font.pixelSize.*`, `Appearance.rounding.*`, `Appearance.sizes.*`. Animation: `Appearance.animation.*` presets.
- Expose customization as `property color col...` / `property real ...` with `Appearance` defaults (see `RippleButton.qml:26-31`).
- Strings through `Translation.tr()`.
- `pragma ComponentBehavior: Bound` + `required property` for delegates.
- Format: 4 spaces, ≤110 columns (`.qmlformat.ini`).

Defaults for `config.json` live in `Config.qml` itself; there is no separate defaults file.

## Gotchas

- **Schema/usage mismatch**: `Config.qml:402` defines `notifications.monitor.{enable,name}`, but `modules/ii/notificationPopup/NotificationPopup.qml:17` and `modules/settings/InterfaceConfig.qml:272-289` use `notifications.forceMonitor.*`, which is not declared, so the "force monitor" setting is not backed by the schema (likely broken/not persisted; unverified at runtime). Always grep for both the declaration and the uses when touching an option.
- Writing to `Config.options` rewrites the entire user `config.json` (formatting/comments lost); hand-edited files must be valid JSON.
- Setting a nested `JsonObject` wholesale (e.g. `Config.options.bar = {...}`) is not the pattern used anywhere; assign leaf properties.
- `list<var>`/`list<string>` changes must reassign the list (`x = [...x, item]`); in-place `push` may not trigger `adapterUpdated` (standard QML list semantics; unverified for JsonAdapter specifically).
- `setNestedValue` converts numeric-looking strings to numbers; a string option holding digits (e.g. a city code) would become a number.
- Two processes can write the same file (main shell + settings app); last write wins after the 50 ms debounce. The settings app sets `readWriteDelay = 0` to minimise races.
- `Appearance.m3colors` defaults are a pinkish fallback palette; if `colors.json` is missing (theming never ran) the shell uses them.
- `Directories.state`/`cache` include the `quickshell` app dir, but `Directories.config` does not; the shell config lives in `~/.config/illogical-impulse`, not `~/.config/quickshell`.
