# Waffle panel family

## Purpose and scope

Waffle is the Windows-11-style shell family in `dots/.config/quickshell/ii/modules/waffle/`. Its [README](../../dots/.config/quickshell/ii/modules/waffle/README.md) calls it WIP; its old “currently there's just the bar” note does not describe the current family composition.

Paths below are repo-relative. For compactness, `Q` means `dots/.config/quickshell/ii`, and `W` means `dots/.config/quickshell/ii/modules/waffle`. An abbreviated source reference such as `W/bar/WaffleBar.qml:14` expands using those prefixes. State, persistence, and service internals belong in [architecture](architecture.md), [config and common](config-and-common.md), and [services](services.md). The [ii family](panels-ii.md) supplies several fallbacks.

## Family selection and shared infrastructure

- `Q/shell.qml:37` cycles `Config.options.panelFamily` through `ii` and `waffle`. Its two `PanelFamilyLoader`s require `Config.ready` and the matching identifier; this switches live by loading/unloading the family, without restarting the shell.
- Installed-shell command: `qs -c ii ipc call panelFamily cycle`. The matching global shortcut is `quickshell:panelFamilyCycle` (`Q/shell.qml:62`). Current Hyprland binding is **Ctrl+Super+P**, in `dots/.config/hypr/hyprland/keybinds.lua:58`. Waffle's README still advertises Super+Alt+W; use the Lua binding as the current source.
- The Quickshell config name remains `ii`; `waffle` is a family inside that config. The schema defaults to `panelFamily: "ii"` (`Q/modules/common/Config.qml:81`).
- `Q/panelFamilies/WaffleFamily.qml:26` instantiates all waffle entry components through `PanelLoader`, whose only default gate is `Config.ready` (`Q/panelFamilies/PanelLoader.qml:6`). Per-panel visibility is controlled inside each entry.
- The family imports **ii Cheatsheet, OnScreenKeyboard, Overlay, ScreenTranslator, and WallpaperSelector** as fallbacks (`Q/panelFamilies/WaffleFamily.qml:19`). There is no active waffle overlay; its import and loader are commented out.
- `Q/GlobalStates.qml:12` is shared across families. Names such as `sidebarLeftOpen` describe historical interfaces: waffle's action center uses that state but appears on the **right**. Opening `sidebarRightOpen` times out notification popups and marks notifications read (`Q/GlobalStates.qml:34`).

## Entry map

Entry paths are relative to `W/`. IPC calls below use `qs -c ii ipc call TARGET METHOD`; global shortcuts are registered under `quickshell:NAME`.

| Area | Entry / purpose | Visibility and external controls |
| --- | --- | --- |
| actionCenter | `actionCenter/WaffleActionCenter.qml` — quick toggles, sliders, devices, media | `sidebarLeftOpen`; IPC `sidebarLeft.toggle`, `mediaControls.toggle`; shortcuts `sidebarLeftToggle`, `mediaControlsToggle` (`:69`) |
| background | `background/WaffleBackground.qml` — wallpaper on every screen | Always instantiated with family; no local IPC/shortcut (`:20`) |
| bar | `bar/WaffleBar.qml` — taskbar on every screen | `barOpen`; IPC `bar.toggle/open/close`; shortcuts `barToggle`, `barOpen`, `barClose` (`:14`, `:46`) |
| lock | `lock/WaffleLock.qml` — clock-first lock surface and password view | Inherits common `LockScreen`: `screenLocked`; IPC `lock.activate/focus`; shortcuts `lock`, `lockFocus` (`Q/modules/common/panels/lock/LockScreen.qml:105`) |
| looks | `looks/Looks.qml` plus `W*` controls — shared waffle styling | Singleton/component library, not a panel |
| notificationCenter | `notificationCenter/WaffleNotificationCenter.qml` — notifications, calendar, focus timer | `sidebarRightOpen`; IPC `sidebarRight.toggle`; shortcut `sidebarRightToggle` (`:69`) |
| notificationPopup | `notificationPopup/WaffleNotificationPopup.qml` — transient notifications | `Notifications.popupList.length > 0 && !screenLocked`; no local IPC/shortcut (`:18`) |
| onScreenDisplay | `onScreenDisplay/WaffleOSD.qml` — volume/brightness indicators | Audio/Brightness changes and `osdVolumeOpen` / `osdBrightnessOpen`; declares IPC `osd.trigger` and shortcut `osdTrigger`, with caveats below (`:30`, `:145`) |
| polkit | `polkit/WafflePolkit.qml` — authentication prompt | Common `FullscreenPolkitWindow` loads while `PolkitService.active`; no local IPC/shortcut |
| screenSnip | `screenSnip/WScreenSnip.qml` — capture/OCR/search/record selection | `regionSelectorOpen`; IPC `region.screenshot/ocr/search/record/recordWithSound`; shortcuts `regionScreenshot`, `regionOcr`, `regionSearch`, `regionRecord`, `regionRecordWithSound` (`:33`) |
| sessionScreen | `sessionScreen/WaffleSessionScreen.qml` — lock, sign-out, password, task manager, power | `sessionOpen`; IPC `session.toggle/open/close`; shortcuts `sessionToggle`, `sessionOpen`, `sessionClose` (`:73`) |
| startMenu | `startMenu/WaffleStartMenu.qml` — pinned/all apps and search | `searchOpen`; IPC `search.toggle/open/close/toggleReleaseInterrupt` (collision below); shortcuts `searchToggle`, `searchToggleRelease`, `searchToggleReleaseInterrupt`, `overviewClipboardToggle`, `overviewEmojiToggle` (`:86`) |
| taskView | `taskView/WaffleTaskView.qml` — window/workspace overview | `overviewOpen`; shortcut `overviewWorkspacesToggle`; IPC `search.toggle/workspacesToggle/open/close/toggleReleaseInterrupt/clipboardToggle` (collision below, `:79`) |

## Styling: Looks, not a separate configuration backend

`W/looks/Looks.qml:9` defines the waffle token singleton:

- `darkColors` and `lightColors` contain largely fixed neutral colors. `colors` derives translucent panel/body/footer/control colors from them (`:31`, `:59`, `:87`).
- `dark` follows `Appearance.m3colors.darkmode` (`:18`). Accent, hover/active accent, and selection colors come from `Appearance.colors` (`:130`). Waffle therefore still responds to shared theme accents and dark mode.
- `appearance.transparency.enable` controls waffle's background/panel transparency (`:20`). Do not assume every common transparency detail is consumed here.
- `radius` supplies 0/2/4/8/12 values; `font` uses its own Noto Sans UI family, weights, and small pixel sizes (`:139`). `transition` defines waffle animations (`:172`). Changing `Appearance.font` alone is not equivalent to changing waffle fonts.
- `FluentIcon.qml:8` resolves `${Looks.iconsPath}/${icon}${filled ? "-filled" : ""}.svg`, defaulting to masked foreground color. Assets live under `Q/assets/icons/fluent`; names are SVG names, not Material-symbol ligatures.
- Reuse `WText`, `WButton`, `WBorderedButton`, `WBorderlessButton`, `WSlider`, `WSwitch`, `WPane`, `WMenu`, and related waffle controls for matching visuals. Common utilities/widgets are still imported throughout the family.

`W/looks/WBarAttachedPanelContent.qml:11` is the action-center/start-menu/notification-center/OSD content shell. It owns `contentItem`, implicit dimensions, `visualMargin`, opening animation, `close()`, and a `closed` signal emitted **after** closing animation (`:62`). Entry loaders typically keep the window alive until that signal, then clear state and deactivate the loader. Preserve this lifecycle when editing panels; immediate destruction skips the animation.

## Panel internals and dependencies

### Action center

`W/actionCenter/WaffleActionCenter.qml:23` creates a right-anchored panel, attached to the configured top/bottom taskbar edge. A `HyprlandFocusGrab` dismisses it when focus leaves (`:42`). Both `sidebarLeft` and `mediaControls` entry points operate `sidebarLeftOpen`; `mediaControlsOpen` is not the controlling state here.

`ActionCenterContent.qml:13` composes an optional `MprisController` media pane and a `WStackView`. `ActionCenterContext.qml:10` holds the stack reference and implements `push()`/`back()`; the main page installs itself as the initial item. Device detail pages live in `wifi/`, `bluetooth/`, `volumeControl/`, and `nightLight/`.

- `mainPage/MainPageBodyToggles.qml:19` pages the configured identifiers into a fixed **3×2** grid, with vertical swipe, scroll, and page buttons. This is independent of ii's sidebar toggle layout.
- `toggles/ActionCenterTogglesDelegateChooser.qml:21` maps strings to shared `modules/common/models/quickToggles` models and waffle visuals. It supplies Fluent icons and optional device/detail pages. Model behavior should be changed in common when it must affect both families.
- Direct dependencies include `Network`, `BluetoothStatus`, `Audio`/PipeWire, `Brightness`, `Battery`, `Hyprsunset`, `EasyEffects`, and `MprisController`; individual shared toggle models add their own dependencies. See [services](services.md) for backend behavior.
- `mainPage/MainPageBodySliders.qml:15` gets brightness for the panel's screen; volume is the default audio sink. `mainPage/MainPageFooter.qml:44` closes the center and launches the separate settings app.
- Config: `waffles.actionCenter.toggles`, `waffles.bar.bottom`; `apps.network`, `apps.bluetooth`, `apps.volumeMixer` for external detail apps; `light.night.automatic`, `light.night.colorTemperature`, `light.antiFlashbang.enable` in the night-light page. Shared toggle models consume further keys; do not treat this list as their schema.

### Background and taskbar

`W/background/WaffleBackground.qml:20` creates a bottom-layer, full-screen wallpaper window per `Quickshell.screens`, using only `background.wallpaperPath` and `PreserveAspectCrop`. It imports ii widget modules but instantiates **no clock/weather/widget canvas or parallax logic**. ii background-widget settings do not add widgets to waffle.

`W/bar/WaffleBar.qml:14` lazy-loads one panel per screen while `barOpen`. It declares `exclusiveZone: implicitHeight` and `exclusionMode: ExclusionMode.Ignore`; inspect compositor behavior before changing either. `WaffleBarContent.qml:13` fixes the content height to 48 and assembles:

- A Widgets button (also opens the action center), a start/search/task-view/apps row, and the right-side tray/update/system/time row.
- `waffles.bar.leftAlignApps` changes app-row alignment and moves the Widgets button into the right-side row (`WaffleBarContent.qml:44`). `waffles.bar.bottom` controls top/bottom placement and popup directions.
- `tasks/Tasks.qml:38` renders `TaskbarApps.apps`, filtering the `SEPARATOR` item. It does not filter tasks to the current workspace. `TaskAppButton.qml`, `TaskPreview.qml`, and `WindowPreview.qml` implement app actions and hover previews. The shared service reads `dock.pinnedApps` and `dock.ignoredAppRegexes` (`Q/services/TaskbarApps.qml:27`, `:41`), so waffle's taskbar shares pin/filter settings with the ii dock.
- `tray/` consumes `TrayService`; system/time buttons consume `Network`, `Audio`, `Battery`, `DateTime`, and `Notifications`. The system button toggles `sidebarLeftOpen`; time toggles `sidebarRightOpen`; task view toggles `overviewOpen`.
- `UpdatesButton.qml` consumes `Updates` and executes `apps.update`. `StartButton.qml:39` uses `apps.terminal`, `apps.taskManager`, and launches `settings.qml` from its context menu. `BarPopup.qml:15` uses `waffles.tweaks.smootherMenuAnimations`.

### Lock and polkit

`W/lock/WaffleLock.qml:19` subclasses common `LockScreen`; the latter owns session locking, shared `LockContext` authentication, keyring unlocking, startup behavior, and the Hyprlock alternative. The waffle file supplies the surface: wallpaper, initially clock/status view, then animated blurred password view after interaction (`:22`, `:103`). Password input updates `context.currentText` and calls `context.tryUnlock()` (`:291`). It uses `DateTime`, `SystemInfo`, and `WIcons` status helpers; the power control is reused from waffle sessionScreen.

Config consumed by this surface: `background.wallpaperPath`. Inherited common behavior uses `lock.useHyprlock`, `lock.launchOnStartup`, `lock.security.unlockKeyring` (`Q/modules/common/panels/lock/LockScreen.qml:87`, `:105`, `:145`). Waffle's blur amount and clock placement are coded in its surface; do not assume ii lock styling options apply.

`W/polkit/WafflePolkit.qml:10` supplies `WPolkitContent` to `Q/modules/common/widgets/FullscreenPolkitWindow.qml:14`, which creates an overlay on every screen only while `PolkitService.active`. `WPolkitContent.qml:105` binds message, prompt, enabled state, submit, and cancel to that service. It uses `background.wallpaperPath`; it has no independent global toggle or waffle-specific config group. Authentication logic belongs in the service/common code, not in the visual prompt.

### Notification center and popups

`W/notificationCenter/WaffleNotificationCenter.qml:23` creates a right-edge, full-height panel with focus-grab dismissal. `NotificationCenterContent.qml:13` reveals it from the right and combines:

- `NotificationPaneContent.qml:61`: `Notifications.appNameList` → `WNotificationGroup` → `WSingleNotification`. Silent-mode toggle and clear-all call the shared `Notifications` service (`:38`).
- `DateHeader.qml` and `CalendarWidget.qml`: `DateTime`, `calendar.locale`, and `waffles.calendar.force2CharDayOfWeek` (`CalendarWidget.qml:21`, `:57`).
- `FocusFooter.qml:28`: `TimerService` pomodoro controls; ±5-minute buttons directly change `time.pomodoro.focus`. Starting focus also issues a `sidebarRight.toggle` IPC call (`:67`).

`NotificationCenterContent.qml:54` uses `hacks.arbitraryRaceConditionDelay` when recalculating notification-pane height. Preserve/recheck that timing if changing its layout.

`W/notificationPopup/WaffleNotificationPopup.qml:18` displays `Notifications.popupList` on the focused Hyprland monitor, suppressing it while locked. It reuses `WSingleNotification`, so change that component for consistent center/popup rendering. The window spans the right edge but masks input to list content (`:31`). It chooses its screen directly; it does not read a force-monitor option locally. Timeout/filter policy belongs in `Notifications`, not this window.

### OSD

`W/onScreenDisplay/WaffleOSD.qml:16` maps volume/brightness IDs to component URLs and global-state names. Audio volume/mute changes trigger volume only once `Audio.ready`; brightness changes select brightness (`:30`). The indicator loader animates the previous indicator closed before switching source (`:123`).

`OSDValue.qml:11` supplies the common icon/progress/number panel and auto-close timer using `osd.timeout`. `VolumeOSD` binds default-sink volume and restarts the timer on changes. `BrightnessOSD` reads brightness for the focused screen and hides the number. Placement uses `waffles.bar.bottom`; visuals use `Looks`.

### Screen snipping

`W/screenSnip/WScreenSnip.qml:24` loads one `WRegionSelectionPanel` when `regionSelectorOpen` is set. The requested action selects image copy/OCR/search or video recording/recording with sound. The panel supplies rectangle/window selection, quick markup (Ctrl+E), search, OCR, color picker, and close controls.

`WRegionSelectionPanel.qml:70` runs common `TempScreenshotProcess`, displays a frozen `ScreencopyView`, and becomes visible after preparation completes. Window targeting uses `HyprlandData.windowList`/active workspace and monitor scale (`:61`). On drag release, it converts coordinates by scale and delegates to common `ScreenshotAction.getCommand`, then starts the command detached and closes (`:158`). Save-directory input is `screenSnip.savePath` (`:162`). For subprocess/script changes, follow [config and common](config-and-common.md) and [services](services.md) rather than duplicating the shared command builder.

### Session screen

`W/sessionScreen/WaffleSessionScreen.qml:18` loads a full-screen black overlay with exclusive keyboard focus. Opening refreshes `SessionWarnings`; locking closes it. Escape dismisses it. `SessionScreenContent.qml:23` provides Lock, Sign out, Change password, Task Manager, Cancel and keyboard navigation. `PowerButton.qml:65` delegates shutdown/restart to common `modules/common/functions/Session.qml`.

There is no `waffles.sessionScreen` config object. Common `Session` reads `apps.changePassword` and `apps.taskManager` (`Q/modules/common/functions/Session.qml:15`, `:32`); the visual files call it instead of owning shutdown commands. Waffle's `PowerButton` calls `Session.poweroff()`/`reboot()` directly; unlike an authenticated `LockContext` action, these paths do not inspect `lock.security.requirePasswordToPower`. The entry's declared `focusedScreen` property is not assigned to `PanelWindow.screen`; focused-monitor placement is unverified.

### Start menu and task view

`W/startMenu/WaffleStartMenu.qml:17` clears `LauncherSearch.query` on opening and after closing; its content survives until the close animation completes. It attaches to the bar edge and optionally the left edge (`waffles.bar.bottom`, `waffles.bar.leftAlignApps`). Focus leaving dismisses it.

- `StartMenuContent.qml:85` binds search text to `LauncherSearch.query`, forwards acceptance through `StartMenuContext`, and swaps start/search content. It contains hardcoded width/height values (`:88`, `:104`).
- `startPage/StartPageApps.qml:35` builds the pinned grid from `launcher.pinnedApps` with `DesktopEntries.byId`; the All section uses category grids. `StartAppButton.qml` calls `LauncherApps` to reorder/pin Start apps and `TaskbarApps` to pin taskbar apps. These are separate pin lists.
- `StartMenuContext.qml:29` maps category tabs to `search.prefix.app/action/clipboard/emojis/math/shellCommand/webSearch`; shared `LauncherSearch` owns search execution. `searchPage/SearchResults.qml` renders results and per-result actions, with Start/taskbar pin commands (`:205`). User controls consume `SystemInfo`, `apps.manageUser`, and common `Session`.
- `waffles.tweaks.smootherSearchBar` controls search-bar transition behavior (`SearchBar.qml:33`). Clipboard/emoji shortcut helpers ensure their configured search prefix even if the menu was already open (`WaffleStartMenu.qml:73`).

`W/taskView/WaffleTaskView.qml:19` has per-screen loaders, activated on `overviewOpen` changes. `TaskViewContent.qml:63` filters toplevels to the **active workspace**, arranges them with `window-layout.js`, and renders windows plus a workspace strip. Dragging a window onto a workspace dispatches a Lua Hyprland window move (`:188`); clicking a workspace focuses it (`:295`). `TaskViewWindow.qml` supports focus/close/pin. Dependencies: Quickshell `ToplevelManager`, `HyprlandData`, `AppSearch`, and Hyprland dispatch; workspace previews use `background.wallpaperPath`. ii's `overview.rows/columns/scale` configuration is not read in these files.

## Waffle-specific schema and recipes

`Q/modules/common/Config.qml:611` defines **`waffles` (plural)**, while the family identifier and directory are **`waffle` (singular)**:

| Key below `Config.options.waffles` | Default / consumer |
| --- | --- |
| `tweaks.switchHandlePositionFix` | `true`; `looks/WSwitch.qml:49` |
| `tweaks.smootherMenuAnimations` | `true`; `bar/BarPopup.qml:15` |
| `tweaks.smootherSearchBar` | `true`; `startMenu/SearchBar.qml:33` |
| `bar.bottom` | `true`; bar and attached panel placement |
| `bar.leftAlignApps` | `false`; taskbar alignment and Start positioning |
| `actionCenter.toggles` | Ordered string list; chooser roles listed in `actionCenter/toggles/ActionCenterTogglesDelegateChooser.qml` |
| `calendar.force2CharDayOfWeek` | `true`; calendar weekday abbreviation |

To change taskbar position/alignment, edit the `waffles.bar` values in the persisted config (see [config and common](config-and-common.md)); the settings app's current Bar controls write the ii `bar` group, not `waffles.bar`.

To add an action-center toggle: reuse/add the common quick-toggle model, add a `DelegateChoice` with the exact identifier in `W/actionCenter/toggles/ActionCenterTogglesDelegateChooser.qml`, supply a Fluent icon and optional detail-page `Component`, and add the identifier to the default/user `waffles.actionCenter.toggles` list. Match `ActionCenterToggleButton.qml`'s `toggleModel` contract. Merely adding a model or config string does not create the waffle delegate.

To add a detail page: follow `wifi/WifiControl.qml` or `volumeControl/VolumeControl.qml`; navigate through `ActionCenterContext.push(component)`/`back()` and retain `WPanelPageColumn`/header/footer conventions. To expose its config in Settings, follow [settings app](settings-app.md).

To adjust shared notification visuals, edit `WSingleNotification.qml` and check both center and popup usage. To change waffle-only colors/spacing/fonts, begin in `looks/Looks.qml`; adjust common `Appearance` only when both families should change.

## Gotchas and unverified runtime behavior

These are static-code observations, not runtime diagnoses; no shell/compositor was launched for this documentation.

- Both `WaffleStartMenu.qml:86` and `WaffleTaskView.qml:79` register IPC target **`search`** with overlapping methods. Task View adds `workspacesToggle` and a `clipboardToggle` that calls an undefined `overviewScope.toggleClipboard()`. IPC collision resolution is **unverified**. The distinct `overviewWorkspacesToggle` global shortcut is clear in source; do not promise that `search.toggle` reliably addresses either UI.
- `WaffleOSD.qml:149` and `:157` call `root.trigger()`, but the root defines only `triggerBrightnessOsd()` and `triggerVolumeOSD()`. Its monitor-change handler writes `osdRoot.screen` (`:91`), although this file's panel ID is `panelWindow`. Automatic Audio/Brightness connections exist; manual trigger and monitor-change behavior need runtime verification/fixing.
- `WRegionSelectionPanel.qml:39` emits `closed()` and references/sets `videoAction`, but declares neither a `closed` signal nor a `videoAction` property. `WScreenSnip.qml` depends on both. Treat recording and panel construction/closure as unverified rather than assuming parity with ii's region selector.
- `WBarAttachedPanelContent.qml:34` handles Escape with `content.close()` rather than `root.close()`; this relies on a caller-context identifier. Preserve focus/grab and closure paths when extracting/reusing it, and verify Escape in each consumer.
- Per-screen behavior differs: wallpaper/bar/task view explicitly iterate screens; notification popups explicitly choose the focused monitor; several other panels leave `screen` implicit. Do not generalize one panel's monitor logic to the family.
- Many dimensions are fixed; the README explicitly discusses scaling with `QT_SCALE_FACTOR`. Avoid assuming common ii sizing/font settings control every waffle component.
