# ii panel family (`modules/ii/**`)

The default "illogical-impulse" (Material You) panel set. All paths below are relative to
`dots/.config/quickshell/ii/` unless they start with `dots/` or `docs/`.

Related docs: [architecture.md](architecture.md) (shell entry, panel families),
[config-and-common.md](config-and-common.md) (`Config`, `Appearance`, `Persistent`, common widgets),
[services.md](services.md) (singletons in `services/`), [panels-waffle.md](panels-waffle.md),
[settings-app.md](settings-app.md), [../hyprland.md](../hyprland.md) (keybinds, layer rules).

## How ii panels get loaded

- `shell.qml` loads `panelFamilies/IllogicalImpulseFamily.qml` through a `LazyLoader` when
  `Config.options.panelFamily === "ii"` (`shell.qml:44-57`). `Ctrl+Super+P` / GlobalShortcut
  `panelFamilyCycle` / IPC `panelFamily cycle` switches between `"ii"` and `"waffle"`.
- `IllogicalImpulseFamily.qml` has one `PanelLoader { component: X {} }` per module.
  `PanelLoader` (`panelFamilies/PanelLoader.qml`) is a `LazyLoader` with
  `active: Config.ready && extraCondition`. Conditional ones:
  - `Bar` if `!Config.options.bar.vertical`, `VerticalBar` if `Config.options.bar.vertical`
  - `Dock` if `Config.options.dock.enable`
- The waffle family reuses these ii modules as fallbacks: `Cheatsheet`, `OnScreenKeyboard`,
  `Overlay`, `ScreenTranslator`, `WallpaperSelector` (`panelFamilies/WaffleFamily.qml:19-24`).
  So a change to those affects both families.
- There are **no `qmldir` files** in `modules/ii`. Each directory is an implicit QML module,
  imported as `qs.modules.ii.<dir>` (e.g. `import qs.modules.ii.sidebarRight.quickToggles.androidStyle`).
  A new `PascalCase.qml` file in a directory is automatically a type in that module.

## Shared state and control surface

`GlobalStates.qml` (singleton at shell root, `import qs`) holds the open/closed flags:
`barOpen` (default true), `sidebarLeftOpen`, `sidebarRightOpen`, `mediaControlsOpen`,
`osdBrightnessOpen`, `osdVolumeOpen`, `oskOpen`, `overlayOpen`, `overviewOpen`,
`regionSelectorOpen`, `screenLocked`, `screenTranslatorOpen`, `sessionOpen`,
`wallpaperSelectorOpen`, `crosshairOpen`, `searchOpen`, `superDown`,
`superReleaseMightTrigger`, `workspaceShowNumbers`, plus lock-screen helpers.
Side effects: opening the right sidebar calls `Notifications.timeoutAll()` + `markAllRead()`
(`GlobalStates.qml:34-39`). It also defines GlobalShortcut `workspaceNumber` (sets `superDown`
while Super is held).

Each panel exposes three ways to drive it, all just flipping a `GlobalStates` flag:
- `IpcHandler { target: "<name>" }` → `qs -c ii ipc call <target> <fn>` (Hyprland binds use
  `qs -c $qsConfig ipc call`, `dots/.config/hypr/hyprland/keybinds.lua:9`).
- `GlobalShortcut { name: "<name>" }` → Hyprland `hl.dsp.global("quickshell:<name>")`
  (keybinds in `dots/.config/hypr/hyprland/keybinds.lua`).
- Clicks from other panels (bar, screen corners) setting `GlobalStates.*` directly.

### Control table

| Module | Flag | IPC target: functions | GlobalShortcut names | Default bind (`keybinds.lua`) |
|---|---|---|---|---|
| bar / verticalBar | `barOpen` | `bar`: toggle/open/close | `barToggle`, `barOpen`, `barClose` | Super+J |
| cheatsheet | (loader-local, no flag) | `cheatsheet`: toggle/open/close | `cheatsheetToggle/Open/Close` | Super+/ |
| lock (base in `modules/common/panels/lock/LockScreen.qml`) | `screenLocked` | `lock`: activate, focus | `lock`, `lockFocus` | Super+L → `loginctl lock-session`; hypridle `lock_cmd` dispatches `quickshell:lock` (`dots/.config/hypr/hypridle.conf:1`) |
| mediaControls | `mediaControlsOpen` | `mediaControls`: toggle/open/close | `mediaControlsToggle/Open/Close` | Super+M |
| onScreenDisplay | `osdVolumeOpen` | `osdVolume`: trigger/hide/toggle | `osdVolumeTrigger`, `osdVolumeHide` | — (auto on volume/brightness change) |
| onScreenKeyboard | `oskOpen` | `osk`: toggle/open/close | `oskToggle/Open/Close` | Super+K |
| overlay | `overlayOpen` | `overlay`: toggle | `overlayToggle` | Super+G |
| overview (+ search) | `overviewOpen` | `search`: toggle, workspacesToggle, open, close, toggleReleaseInterrupt, clipboardToggle, … | `searchToggle`, `searchToggleRelease`, `searchToggleReleaseInterrupt`, `overviewWorkspacesToggle`, `overviewWorkspacesClose`, `overviewClipboardToggle`, `overviewEmojiToggle` | Super (tap) → `searchToggleRelease`; Super+Tab; Super+V; Super+.; 4-finger swipe up/down (`general.lua:23-36`) |
| regionSelector | `regionSelectorOpen` | `region`: screenshot, search, ocr, record, recordWithSound | `regionScreenshot`, `regionSearch`, `regionOcr`, `regionRecord`, `regionRecordWithSound` | Super+Shift+S/A/X; Super+Shift+R and Super+Alt+R both → `regionRecord`; `regionRecordWithSound` unbound |
| screenTranslator | `screenTranslatorOpen` | `screenTranslator`: translate | `screenTranslate` | Super+Shift+T |
| sessionScreen | `sessionOpen` | `session`: toggle/open/close | `sessionToggle/Open/Close` | Ctrl+Alt+Delete |
| sidebarLeft | `sidebarLeftOpen` | `sidebarLeft`: toggle/open/close | `sidebarLeftToggle/Open/Close`, `sidebarLeftToggleDetach` | Super+A/B/O, Super+Alt+A (detach) |
| sidebarRight | `sidebarRightOpen` | `sidebarRight`: toggle/open/close | `sidebarRightToggle/Open/Close` | Super+N |
| wallpaperSelector | `wallpaperSelectorOpen` | `wallpaperSelector`: toggle, random | `wallpaperSelectorToggle`, `wallpaperSelectorRandom` | Ctrl+Super+T, Ctrl+Super+Alt+T |
| background, dock, notificationPopup, polkit, screenCorners | — | — | — | always-on / service-driven |

Note: `Bar.qml` and `VerticalBar.qml` both declare IPC target `bar` and the same shortcuts; only
one is loaded at a time (mutually exclusive `extraCondition`).

Keybind fallbacks: several binds are doubled with `qsIsAlive || <fallback>` (e.g. Super tap →
fuzzel, region record → `scripts/videos/record.sh`) so they work when quickshell is dead
(`keybinds.lua:12-15, 86-90`).

### Layer-shell namespaces

Every window sets `WlrLayershell.namespace: "quickshell:<name>"`; Hyprland layer rules match on
these (`dots/.config/hypr/hyprland/rules.lua:136-171`: blur for `quickshell:.*`, per-namespace
animations such as `sidebarRight` → `slide right`, `overview`/`session`/`regionSelector` → `no_anim`).
**If you add a panel, pick a namespace and add rules there if it needs a specific animation**;
renaming a namespace silently drops its rules. Namespaces used by ii: `background`, `bar`,
`verticalBar`, `popup` (bar hover popups), `cheatsheet`, `dock`, `mediaControls`,
`notificationPopup`, `onScreenDisplay`, `osk`, `overlay`, `overview`, `polkit`,
`regionSelector` (also used by `ScreenTranslatorPanel.qml:23`), `screenCorners`, `session`,
`sidebarLeft`, `sidebarRight`, `wallpaperSelector`.

## Shared panel patterns

**Skeleton** (see `sidebarRight/SidebarRight.qml` as the minimal reference, 110 lines):

```qml
Scope {
    PanelWindow {
        visible: GlobalStates.fooOpen
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:foo"
        WlrLayershell.keyboardFocus: GlobalStates.fooOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"
        anchors { top: true; right: true; bottom: true }
        onVisibleChanged: visible ? GlobalFocusGrab.addDismissable(this) : GlobalFocusGrab.removeDismissable(this)
        Connections { target: GlobalFocusGrab; function onDismissed() { GlobalStates.fooOpen = false } }
        Loader { active: GlobalStates.fooOpen; focus: ...; Keys.onPressed: /* Esc closes */; sourceComponent: FooContent {} }
    }
    IpcHandler { target: "foo"; function toggle(): void { ... } }
    GlobalShortcut { name: "fooToggle"; onPressed: ... }
}
```

Variants seen in the codebase:
- **Window always exists, content lazily loaded**: sidebarRight (content `Loader` active when open
  *or* `Config.options.sidebar.keepRightSidebarLoaded`, default true → component state survives
  closing, though Wi-Fi/Bluetooth/audio-output/audio-input dialogs are explicitly reset on close), overview (`Loader` for `OverviewWidget`).
- **Whole window inside a `Loader`/`LazyLoader`** gated on the flag: cheatsheet, mediaControls,
  OSD, OSK, overlay, sessionScreen, wallpaperSelector, screenTranslator. Window is destroyed on close.
- **Per-monitor via `Variants { model: Quickshell.screens }`**: background, bar/verticalBar
  (filtered by `Config.options.bar.screenList`), dock, lock push-down, regionSelector,
  screenCorners, polkit (`modules/common/widgets/FullscreenPolkitWindow.qml`).
- **Focused-monitor only**: OSD (`screen = focusedScreen` on open), notificationPopup
  (`Hyprland.focusedMonitor`, or `Config.options.notifications.forceMonitor.{enable,name}`),
  screenTranslator (screen captured at open time in `lockedScreen`).
- **No explicit `screen`** (unverified which output the compositor picks; likely the focused one):
  overview, sidebars, cheatsheet, mediaControls, sessionScreen, wallpaperSelector, OSK.
- **Input masks**: windows that span the screen but should be click-through outside their card
  set `mask: Region { item: <background item> }` (sidebarLeft, cheatsheet, bar hover region,
  overview, overlay, dock, popups).

**Focus grabbing — `services/GlobalFocusGrab.qml`**: one shared `HyprlandFocusGrab`.
- `addDismissable(win)` / `removeDismissable(win)`: popups that should close on click-outside
  (sidebars, cheatsheet, mediaControls, overview, wallpaperSelector). When the grab is cleared it
  emits `dismissed()`; every dismissable listens and closes itself.
- `addPersistent(win)`: windows included in the grab but never dismissed (bar, vertical bar, OSK),
  so clicking the bar doesn't close a sidebar. Persistent windows are only included when a
  dismissable has active focus or none are focusable (`GlobalFocusGrab.qml` `windows:` binding).
- `dismiss()` force-closes all dismissables (overview calls it on close).
- Overlay uses its **own** `HyprlandFocusGrab` with a delayed activation (`overlay/Overlay.qml:47-60`).

**Keyboard focus**: `WlrKeyboardFocus.OnDemand` while open (sidebars, overview, wallpaper,
region selector); `Exclusive` for sessionScreen and overlay-while-open. Comment at
`sidebarLeft/SidebarLeft.qml` (keyboardFocus line): on Hyprland ≥0.49 `Exclusive` breaks
click-outside-to-close, so use `OnDemand`. Cheatsheet deliberately leaves keyboardFocus unset
("takes its sweet time to open").

**Animations**: use `Appearance.animation.<elementMove|elementMoveFast|elementMoveSmall>`
via `Behavior on x { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }`
(or `.colorAnimation`). Window open/close animations are mostly done by Hyprland layer rules,
not QML. `FadeLoader { shown: … }` (common widget) is used for fade-in/out sub-content.

**Styling**: colors from `Appearance.colors.colLayer0..3`, `colPrimary`, `m3colors.*`; sizes from
`Appearance.sizes.*` (`sidebarWidth`, `barHeight`, `baseBarHeight`, `verticalBarWidth`,
`hyprlandGapsOut`, `elevationMargin`); rounding `Appearance.rounding.*`. Strings go through
`Translation.tr("…")`. See [config-and-common.md](config-and-common.md).

**Hyprland dispatch syntax**: this repo targets Lua-config Hyprland, so dispatches are Lua
expressions: `Hyprland.dispatch("hl.dsp.focus({workspace = 3})")`,
`hyprctl dispatch 'hl.dsp.cursor.move({x=…,y=…})'` (`bar/Workspaces.qml`, `sidebarLeft/SidebarLeft.qml`,
`lock/Lock.qml`). Old-style `workspace 3` dispatch strings won't work.

## Modules

### background — `background/Background.qml`
Wallpaper + desktop widgets. `Variants` over all screens, `WlrLayer.Bottom` normally, switched to
`WlrLayer.Overlay` while locked (so it renders behind the lock surface with blur/zoom,
`Config.options.lock.blur.{enable,radius,extraZoom}`). Hidden when the active workspace has a
fullscreen window if `Config.options.background.hideWhenFullscreen`.
- Wallpaper: `Config.options.background.wallpaperPath`; for videos (`.mp4/.webm/.mkv/.avi/.mov`)
  shows `background.thumbnailPath` (video playback itself is external).
- Parallax: `background.parallax.{workspaceZoom, enableWorkspace, enableSidebar, vertical, autoVertical, widgetsFactor}`
  — wallpaper shifts with workspace index and open sidebars.
- Work safety: `workSafety.enable.wallpaper` + `workSafety.triggerCondition.*` blur/hide
  "unsafe" wallpapers on matching network names.
- Widgets (`background/widgets/`) sit in a `WidgetCanvas` (common widget): `clock/ClockWidget.qml`
  (styles `cookie` / `digital` via `background.widgets.clock.style` / `styleLocked`, cookie sub-parts
  hands/marks/date indicators/quote), `weather/WeatherWidget.qml`. Base class
  `widgets/AbstractBackgroundWidget.qml`: `configEntryName` → `Config.options.background.widgets[name]`,
  `placementStrategy` `"free"` (draggable, x/y stored in config) / `"leastBusy"` / `"mostBusy"`
  (computed by a script over the wallpaper), `visibleWhenLocked`, auto text color from wallpaper.

### bar — `bar/Bar.qml` → `bar/BarContent.qml`
Horizontal top/bottom bar.
- `Variants` over `Quickshell.screens` filtered by `Config.options.bar.screenList` (empty = all),
  each a `LazyLoader` active when `GlobalStates.barOpen && !GlobalStates.screenLocked`.
- Layer: namespace `quickshell:bar`, `exclusionMode: Ignore` with manual `exclusiveZone`
  (`baseBarHeight`, +gaps for float style; 0 when auto-hidden unless `autoHide.pushWindows`).
  Window is taller than the bar (`barHeight + screenRounding`) to draw rounded "hug" corners;
  input mask = `hoverMaskRegion`.
- Auto-hide: `bar.autoHide.{enable, hoverRegionWidth, pushWindows, showWhenPressingSuper.{enable,delay}}`
  (reveals on hover or while Super is held via `GlobalStates.superDown`).
- Registered as **persistent** in `GlobalFocusGrab`.
- Other keys: `bar.bottom`, `bar.cornerStyle` (0 hug / 1 float / 2 rect), `bar.floatStyleShadow`,
  `bar.borderless`, `bar.showBackground`, `bar.verbose`, `bar.topLeftIcon`,
  `bar.resources.*`, `bar.utilButtons.show*`, `bar.workspaces.*`, `bar.weather.*`,
  `bar.indicators.notifications.showUnreadCount`, `bar.tooltips.clickToShow`,
  `interactions.deadPixelWorkaround.enable`.

**Layout is hard-coded in `BarContent.qml`** — there is no config-driven widget list. Sections:
1. Left `FocusedScrollMouseArea` (scroll = `Brightness.increase/decreaseBrightness()`, click toggles
   left sidebar): `LeftSidebarButton` (dot while `T3.attentionCount > 0`), `ActiveWindow`.
2. Middle `Row` of three `BarGroup`s: [`Resources`, `Media`] · [`Workspaces`] (right-click toggles
   overview) · clickable group [`ClockWidget`, `UtilButtons`, `BatteryIndicator`] (click toggles right sidebar).
3. Right `FocusedScrollMouseArea` (scroll = `Audio.increment/decrementVolume()`), `RowLayout`
   with `layoutDirection: RightToLeft`: right-sidebar `RippleButton` with status icons
   (mute, mic mute, `HyprlandXkbIndicator`, `NotificationUnreadCount`, network, bluetooth), `SysTray`,
   spacer, optional `WeatherBar` (`Loader` on `bar.weather.enable`).
- Responsiveness: `useShortenedForm` 0/1/2 from screen width vs
  `Appearance.sizes.bar{,Hella}ShortenScreenWidthThreshold`; widgets hide via `visible:` on it.

Bar widget files (`bar/`): `ActiveWindow`, `BatteryIndicator`+`BatteryPopup`, `ClockWidget`+`ClockWidgetPopup`,
`HyprlandXkbIndicator`, `LeftSidebarButton`, `Media`, `NotificationUnreadCount`, `Resources`/`Resource`+`ResourcesPopup`,
`SysTray`/`SysTrayItem`/`SysTrayMenu`/`SysTrayMenuEntry`, `UtilButtons`/`CircleUtilButton`, `Workspaces`,
`weather/WeatherBar`+`WeatherPopup`+`WeatherCard`, helpers `BarGroup`, `ScrollHint`,
`StyledPopup`, `StyledPopupHeaderRow`, `StyledPopupValueRow`.
- `BarGroup.qml`: rounded `colLayer1` pill (transparent if `bar.borderless`) wrapping a `GridLayout`
  (`default property alias items`); `vertical: true` makes it a 1-column group for the vertical bar.
- `StyledPopup.qml`: hover popup = `LazyLoader` active while `hoverTarget.containsMouse`; spawns a
  separate `PanelWindow` (namespace `quickshell:popup`, `WlrLayer.Overlay`) positioned with
  `QsWindow.mapFromItem` relative to the bar orientation. Widgets with popups are `MouseArea`s with
  `hoverEnabled: !Config.options.bar.tooltips.clickToShow` and contain e.g. `BatteryPopup { hoverTarget: root }`.
- `Workspaces.qml`: uses `WorkspaceModel` (`qs.modules.common.models`) per monitor, left-click focuses,
  right-click overview, back-button toggles special workspace, wheel `r±1`; shows numbers while
  Super held after `bar.workspaces.showNumberDelay`.
- `UtilButtons.qml`: each button is a `Loader` gated on `bar.utilButtons.show*` (screen snip calls
  `qs -p <shell> ipc call region screenshot`, record, color picker `hyprpicker -a`, mic, keyboard, dark mode, power profile).

### verticalBar — `verticalBar/VerticalBar.qml` → `VerticalBarContent.qml`
Near-copy of `Bar.qml` rotated: anchors left (or right if `bar.bottom`), namespace
`quickshell:verticalBar`, zone `baseVerticalBarWidth`. Loaded only when `Config.options.bar.vertical`.
Imports the horizontal widgets with `import qs.modules.ii.bar as Bar` and reuses most of them
(`Bar.Workspaces`, `Bar.SysTray`, …); vertical-specific files: `BatteryIndicator`, `Resource(s)`,
`VerticalClockWidget`, `VerticalMedia`. Changes to bar behaviour usually need mirroring in both
`Bar.qml`/`BarContent.qml` and `VerticalBar.qml`/`VerticalBarContent.qml`.

### cheatsheet — `cheatsheet/Cheatsheet.qml`
Full-screen-anchored, masked window with tabs "Keybinds" (`CheatsheetKeybinds.qml`,
`CheatsheetKeybindsCategory.qml`, data from `HyprlandKeybinds.keybindCategories` /
`.keybinds` service — parsed from Hyprland config descriptions) and "Elements" (periodic table,
`periodic_table.js`, `ElementTile.qml`). State is the loader's `active`, not a GlobalStates flag.
Keys: `Config.options.cheatsheet.*` (font sizes etc.).

### dock — `dock/Dock.qml`
Bottom dock per screen (`Variants`), loaded only if `dock.enable`. Hidden while locked. Reveal when
pinned (`dock.pinnedOnStartup`, toggleable), hovered (`dock.hoverToReveal`, `dock.hoverRegionHeight`),
requested by `DockApps`, or no active toplevel. `exclusiveZone` only when pinned. Apps from
`TaskbarApps` service (`TaskbarApps.apps`, `togglePin`); keys `dock.height`, `dock.monochromeIcons`,
`dock.pinnedApps`, `dock.ignoredAppRegexes`. Files: `DockApps`, `DockAppButton`, `DockButton`, `DockSeparator`.

### lock — `lock/Lock.qml` (+ `LockSurface.qml`, `PasswordChars.qml`)
Extends `modules/common/panels/lock/LockScreen.qml` (shared with waffle), which owns the
`WlSessionLock`, PAM (`LockContext`), keyring unlock (`scripts/keyring/unlock.sh`), IPC `lock`,
shortcuts `lock`/`lockFocus`, `Config.options.lock.useHyprlock` (delegates to hyprlock),
`lock.launchOnStartup`. ii's `Lock.qml` adds: on lock, moves each monitor to workspace
`2147483647 - ws` (a temp workspace, for the slide-away animation) and restores the saved
workspaces on unlock (`lock/Lock.qml:13-60`). `LockSurface.qml` is the per-screen UI.

### mediaControls — `mediaControls/MediaControls.qml`, `PlayerControl.qml`
Popup under the bar (position adapts to `bar.bottom`/`bar.vertical`) listing MPRIS players from
`MprisController` with duplicate-player filtering (`filterDuplicatePlayers`). Runs `cava` for the
visualizer only while open (`scripts/cava/raw_output_config.txt`). Dismissable focus grab.

### notificationPopup — `notificationPopup/NotificationPopup.qml`
Single window on the focused monitor (or `notifications.forceMonitor`), `WlrLayer.Overlay`,
visible while `Notifications.popupList.length > 0` and not locked. Renders the common
`NotificationListView { popup: true }`.

### onScreenDisplay — `onScreenDisplay/OnScreenDisplay.qml`
Volume/brightness/gamma OSD. Indicators are listed in `indicators` array (`id`, `sourceUrl`
→ `indicators/{Volume,Brightness,Gamma}Indicator.qml`, all built on `OsdValueIndicator.qml`).
Triggered by `Brightness.brightnessChanged`, `Hyprsunset.gammaChangeAttempt`,
`Audio.sink.audio.volume/mutedChanged`, and audio protection (`Audio.sinkProtectionTriggered` →
`protectionMessage`). Timeout `Config.options.osd.timeout`. Shown on focused screen, `WlrLayer.Overlay`.
Note the single flag `osdVolumeOpen` is used for all indicator types.

### onScreenKeyboard — `onScreenKeyboard/OnScreenKeyboard.qml`, `OskContent.qml`, `OskKey.qml`, `layouts.js`
Bottom keyboard, `WlrLayer.Overlay`, persistent focus-grab member, `exclusiveZone` only when pinned
(`osk.pinnedOnStartup`). Layout from `layouts.js` chosen by `Config.options.osk.layout`. Sends keys
via the `Ydotool` service (`press/release/shiftKeys…`). Layer rule `order = -1` for `quickshell:osk`.

### overlay — `overlay/Overlay.qml`
Game-bar-like overlay of floating widgets (Super+G). Window active while `overlayOpen` or any
widget is pinned (`OverlayContext.hasPinnedWidgets`); when closed only pinned/clickable widgets
remain via the mask. Pieces:
- `OverlayContext.qml` (singleton): `availableWidgets` [{identifier, materialSymbol}],
  `pinnedWidgetIdentifiers`, `clickableWidgets`.
- `OverlayContent.qml`: `OverlayTaskbar` + `Repeater` over `Persistent.states.overlay.open`.
- `OverlayWidgetDelegateChooser.qml`: identifier → component.
- `StyledOverlayWidget.qml`: base class (draggable/resizable window-like card; pinned/clickthrough;
  position persisted in `Persistent.states.overlay.<id>`). Its header comment documents the
  4-step "add an overlay widget" recipe (`overlay/StyledOverlayWidget.qml:12-18`).
- Widgets: `crosshair/`, `floatingImage/`, `fpsLimiter/`, `notes/`, `recorder/`, `resources/`, `volumeMixer/`.
- Config: `Config.options.overlay.*`, `crosshair.*`.

### overview — `overview/Overview.qml`
Combined launcher/search + workspace overview, `WlrLayer.Top`, full-screen anchored, masked to the
content column. `SearchWidget.qml`/`SearchBar.qml`/`SearchItem.qml` use `LauncherSearch`
(query/results) with prefixes `Config.options.search.prefix.{app,action,clipboard,emojis,math,shellCommand,webSearch}`.
`OverviewWidget.qml`/`OverviewWindow.qml` draw workspace thumbnails (`overview.{enable,rows,columns,scale,orderBottomUp,orderRightLeft,centerIcons}`),
hidden while search text is non-empty.
- Super tap: `searchToggleRelease` fires on release; any other Super+key combo should call
  `searchToggleReleaseInterrupt` (sets `superReleaseMightTrigger = false`) so the release doesn't open search.
- `toggleClipboard()`/`toggleEmojis()` prefill the search with the clipboard/emoji prefix
  (`dontAutoCancelSearch`).

### polkit — `polkit/Polkit.qml`, `PolkitContent.qml`
`FullscreenPolkitWindow` (common widget) creates a window on every screen while
`PolkitService.active`, `WlrLayer.Overlay`, OnDemand focus. `PolkitContent` is the ii-styled dialog.

### regionSelector — `regionSelector/RegionSelector.qml` → `RegionSelection.qml`
Screenshot/lens/OCR/record region picker. One `RegionSelection` window per screen while
`regionSelectorOpen`. `RegionSelection.SnipAction` {Copy, Edit, Search, CharRecognition, Record,
RecordWithSound} and `SelectionMode` {RectCorners, Circle} (circle for search if
`search.imageSearch.useCircleSelection`). Takes a temp screenshot (`TempScreenshotProcess`),
optionally detects window/layer/content regions (`regionSelector.targetRegions.*`), records via
`Directories.recordScriptPath`; snips saved to `screenSnip.savePath` (empty = clipboard only).
`record()` while open closes then reopens → used to stop recording. Helpers: `CursorGuide`,
`OptionsToolbar`, `TargetRegion`, `RectCornersSelectionDetails`, `CircleSelectionDetails`, `RegionFunctions`.

### screenCorners — `screenCorners/ScreenCorners.qml`
Per screen, 4 `CornerPanelWindow`s (`WlrLayer.Overlay`). Draw fake rounded screen corners
(`appearance.fakeScreenRounding`: 0 none / 1 always / 2 when not fullscreen) and act as hot
corners: top/bottom-left toggles left sidebar, right corners toggle right sidebar
(`actionForCorner`, `ScreenCorners.qml:15-20`); scroll adjusts brightness/volume. Keys
`sidebar.cornerOpen.{enable,bottom,valueScroll,clickless,cornerRegionWidth,cornerRegionHeight,visualize,clicklessCornerEnd,clicklessCornerVerticalOffset}`.

### screenTranslator — `screenTranslator/ScreenTranslator.qml` → `ScreenTranslatorPanel.qml`, `ScreenTextOverlay.qml`
Screenshots the focused monitor and overlays translated text. Uses Google Cloud Vision/Translate
via `modules/common/models/gCloud/GCloudApi.qml` (needs a service-account key; error string
"Set your Google Cloud service account key"). Namespace reuses `quickshell:regionSelector`.

### sessionScreen — `sessionScreen/SessionScreen.qml`, `SessionActionButton.qml`
Full-screen power menu, `WlrLayer.Overlay`, `Exclusive` keyboard focus. Buttons call the `Session`
service: lock, suspend, logout, launchTaskManager, hibernate, poweroff, reboot, rebootToFirmware.
Shows warnings from `SessionWarnings` (downloads / package manager running). Closes when locking.

### sidebarLeft — `sidebarLeft/SidebarLeft.qml` → `SidebarLeftContent.qml`
Left drawer: a read-only **T3 Code navigator** ([t3-sidebar.md](t3-sidebar.md)). Window: namespace
`quickshell:sidebarLeft`, OnDemand focus, dismissable grab, width `sidebarWidth` or
`sidebarWidthExtended`.
- Keys inside: Esc close; Ctrl+O extend width; Ctrl+D **detach** into a `FloatingWindow` (content
  object is created once with `createObject(null)` and re-parented between the PanelWindow and the
  FloatingWindow, so state survives); Ctrl+P **pin** (sets `exclusiveZone` to sidebar width; uses a
  hyprctl cursor-move workaround).
- Content (`SidebarLeftContent.qml`, data from the `T3` service): header with "new thread" (opens a
  project picker, then `t3 app <root>`) and "open T3 Code"; thread sections Pinned / Waiting /
  Working / Snoozed, and Settled collapsed (first 30), as in T3's own sidebar. Rows are `T3ThreadRow.qml` (status icon, title, project,
  relative time). Clicking a row opens it in the T3 window via `t3code://` and closes the drawer
  unless it is pinned or detached. When T3 is unreachable it shows a setup/offline state keyed on
  `T3.error` (copy-token-command, launch button).
- The AI chat, Translator and Anime tabs, and their services, were removed for this.

### sidebarRight — `sidebarRight/SidebarRight.qml` → `SidebarRightContent.qml`
Right drawer (control center). Content column:
1. `SystemButtonRow` (inline component): distro icon + uptime; buttons edit-toggles (android style
   only), reload Hyprland+Quickshell, open settings (`qs -p settings.qml`), session.
2. `QuickSliders.qml` if `sidebar.quickSliders.enable` and any of `showVolume/showMic/showBrightness`.
3. Quick toggle panel: `ClassicQuickPanel` or `AndroidQuickPanel` by `sidebar.quickToggles.style`
   (`"classic"` | `"android"`, default android).
4. `CenterWidgetGroup.qml`: `notifications/NotificationList.qml` (`Notifications` service).
5. `BottomWidgetGroup.qml`: collapsible tabbed group; `tabs` array with `widget` paths
   `calendar/CalendarWidget.qml`, `todo/TodoWidget.qml` (`Todo` service), `pomodoro/PomodoroWidget.qml`
   (`TimerService`: pomodoro + stopwatch). Selected tab and collapsed state in
   `Persistent.states.sidebar.bottomGroup.{tab,collapsed}`.
- Dialogs overlaying the sidebar, opened by panel signals: `VolumeDialog` (sink/source,
  `volumeMixer/`), `BluetoothDialog` (enables adapter + discovery while shown), `NightLightDialog`
  (`Hyprsunset`, `light.night.*`, `light.antiFlashbang.enable`), `WifiDialog` (`Network.rescanWifi()`).
  Implemented with the inline `ToggleDialog` Loader keyed by a `root.show*Dialog` property name.
  Wi-Fi, Bluetooth, audio-output and audio-input dialogs reset when the sidebar closes
  (`SidebarRightContent.qml:32-40`); `showNightLightDialog` is not reset.

#### Quick toggles
Two implementations share a signal interface (`quickToggles/AbstractQuickPanel.qml`:
`openAudioOutputDialog`, `openAudioInputDialog`, `openBluetoothDialog`, `openNightLightDialog`,
`openWifiDialog`), which `SidebarRightContent` wires to the dialogs.
- **Classic** (`quickToggles/ClassicQuickPanel.qml`): a fixed `ButtonGroup` of
  `classicStyle/*.qml` (Network, Bluetooth, NightLight, GameMode, IdleInhibitor, EasyEffects,
  CloudflareWarp), each a `QuickToggleButton` (icon-only `GroupButton`) with its own `toggled`,
  `onClicked`, `altAction` (right-click). Not configurable.
- **Android** (`quickToggles/AndroidQuickPanel.qml`): config-driven grid.
  - Layout: `Config.options.sidebar.quickToggles.android.columns` (default 5) and `.toggles`
    — list of `{ "type": "<id>", "size": 1|2 }`; rows are packed greedily by size.
  - `availableToggleTypes` (`AndroidQuickPanel.qml:33`) lists valid ids: network, bluetooth,
    idleInhibitor, easyEffects, nightLight, darkMode, cloudflareWarp, gameMode, screenSnip,
    colorPicker, onScreenKeyboard, mic, audio, notifications, powerProfile, musicRecognition, antiFlashbang.
  - `androidStyle/AndroidToggleDelegateChooser.qml`: `DelegateChooser` on role `type` → `Android<X>Toggle`,
    passing sizing props and wiring `onOpenMenu` to a dialog signal.
  - Each `androidStyle/Android<X>Toggle.qml` is ~10 lines: `AndroidQuickToggleButton { toggleModel: <X>Toggle {} }`.
  - The logic lives in **shared models** `modules/common/models/quickToggles/<X>Toggle.qml`,
    subclassing `QuickToggleModel.qml` (`name`, `statusText`, `tooltipText`, `icon`, `available`,
    `toggled`, `mainAction`, `hasMenu`, `altAction`, `hasStatusText`). The waffle action center
    reuses the same models (`modules/waffle/actionCenter/toggles/`).
  - `AndroidQuickToggleButton.qml`: size 2 shows name+status; click on a size-2 tile with a menu
    opens it (`altAction`), else `mainAction`. Edit mode (pencil button): LMB enable/disable, RMB
    toggle size, scroll to reorder — it writes `Config.options.sidebar.quickToggles.android.toggles`
    directly (`AndroidQuickToggleButton.qml:191-232`).

### wallpaperSelector — `wallpaperSelector/WallpaperSelector.qml` → `WallpaperSelectorContent.qml`, `WallpaperDirectoryItem.qml`
Top-anchored grid browser for the `Wallpapers` service, `WlrLayer.Overlay`, dismissable grab.
If `Config.options.wallpaperSelector.useSystemFileDialog`, toggling opens
`Wallpapers.openFallbackPicker(...)` instead. `random` → `Wallpapers.randomFromCurrentFolder()`.

## Recipes

### Add a bar widget
1. Create `modules/ii/bar/MyWidget.qml` (root `Item` or `MouseArea` if it needs hover/popup;
   `implicitWidth` from content, `implicitHeight: Appearance.sizes.barHeight`). Use services from
   `qs.services`, colors from `Appearance`.
2. Optional popup: add `MyWidgetPopup.qml` as `StyledPopup { … }` and instantiate it inside the
   widget with `hoverTarget: root`; set `hoverEnabled: !Config.options.bar.tooltips.clickToShow`.
3. Place it in `bar/BarContent.qml` — inside an existing `BarGroup` (e.g. `rightCenterGroupContent`)
   or a new `BarGroup { … }` in `middleSection`, or in `rightSectionRowLayout` (remember it is
   right-to-left). Gate with `visible: root.useShortenedForm === 0` if it should hide on narrow screens.
4. Optional toggle: add `property bool showMyWidget` under `bar` in `modules/common/Config.qml`
   and a switch in the settings app (see [settings-app.md](settings-app.md)); wrap in
   `Loader { active: Config.options.bar.showMyWidget }`.
5. Mirror in `verticalBar/VerticalBarContent.qml` (`Bar.MyWidget` if it works vertically, or a
   vertical variant file).

### Add a quick toggle (android style)
1. Model: `modules/common/models/quickToggles/MyToggle.qml` → `QuickToggleModel { name; icon; toggled; mainAction: () => {…}; statusText; hasMenu?; altAction? }`.
   Put any `Process`/`Timer` objects inside it (default `data` property allows that).
2. Button: `modules/ii/sidebarRight/quickToggles/androidStyle/AndroidMyToggle.qml` →
   `AndroidQuickToggleButton { toggleModel: MyToggle {} }` (import `qs.modules.common.models.quickToggles`).
3. Register the id in `AndroidQuickPanel.qml` `availableToggleTypes` and add a
   `DelegateChoice { roleValue: "myToggle"; AndroidMyToggle { …same boilerplate props… } }` in
   `AndroidToggleDelegateChooser.qml` (copy an existing block; wire `onOpenMenu` if `hasMenu`).
4. Optional default: add `{ "size": 1, "type": "myToggle" }` to `sidebar.quickToggles.android.toggles`
   in `Config.qml` (existing user configs won't get it; users add via edit mode).
5. Classic style: optionally add `classicStyle/MyToggle.qml` (`QuickToggleButton`) to
   `ClassicQuickPanel.qml`. For waffle parity see [panels-waffle.md](panels-waffle.md).

### Add a right sidebar bottom tab
Append `{ type, name, icon, widget: "dir/MyWidget.qml" }` to `tabs` in `sidebarRight/BottomWidgetGroup.qml`
(loaded by path relative to that file).

### Add a new ii panel
1. `modules/ii/myPanel/MyPanel.qml` following the skeleton above (Scope + PanelWindow/Loader,
   unique `WlrLayershell.namespace: "quickshell:myPanel"`, `GlobalFocusGrab` if click-outside should close).
2. Add `property bool myPanelOpen: false` to `GlobalStates.qml`.
3. Add `IpcHandler { target: "myPanel" }` and `GlobalShortcut { name: "myPanelToggle" }`.
4. Register in `panelFamilies/IllogicalImpulseFamily.qml`: `import qs.modules.ii.myPanel` and
   `PanelLoader { component: MyPanel {} }` (add `extraCondition` for a config gate). Add to
   `WaffleFamily.qml` too if it should exist there.
5. Hyprland: bind in `dots/.config/hypr/hyprland/keybinds.lua`
   (`hl.bind("SUPER + X", hl.dsp.global("quickshell:myPanelToggle"), { description = "Shell: …" })`;
   descriptions feed the cheatsheet) and layer rules in `rules.lua` if needed. See [../hyprland.md](../hyprland.md).

## Gotchas

- Bar layout is code, not config; any "bar layout" change means editing `BarContent.qml` *and*
  `VerticalBarContent.qml`.
- `Bar`/`VerticalBar` are swapped by `bar.vertical` via `PanelLoader.extraCondition`; both define IPC
  target `bar`.
- Hyprland dispatch strings are Lua (`hl.dsp.*`), see above.
- `sidebar.keepRightSidebarLoaded` (default true) keeps right sidebar content alive when closed —
  don't rely on `Component.onCompleted` firing on every open; listen to
  `GlobalStates.sidebarRightOpenChanged` instead (as `SidebarRightContent.qml` does).
- The left sidebar content is a single object re-parented between docked and detached windows;
  don't hold references to its parent window.
- Layer namespace strings are referenced from `rules.lua`; `screenTranslator` borrows
  `quickshell:regionSelector`.
- Windows without explicit `screen` appear on whichever output Quickshell/Hyprland chooses
  (unverified: assumed focused monitor).
- The ii OSD uses `osdVolumeOpen` for brightness and gamma too. `osdBrightnessOpen` is only set true
  by waffle (`modules/waffle/onScreenDisplay/WaffleOSD.qml:32`); in ii it is only cleared (`onMovedAway`).
- Android toggle edit mode writes the config JSON directly; `availableToggleTypes` and the
  `DelegateChooser` must both know a type or it silently renders nothing.
- Five ii modules are also loaded by the waffle family (cheatsheet, OSK, overlay, screenTranslator,
  wallpaperSelector) — test both when changing them.
