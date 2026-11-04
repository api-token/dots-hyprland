# Quickshell services

## Scope and source map

The service layer is `dots/.config/quickshell/ii/services/`: 45 singleton QML services, one top-level response data type, six AI helper types, one Wi-Fi access-point type, Google Cloud token scripts, and two GLSL shaders. These are shared by the ii and waffle panel families; availability of a UI does not imply that every service has been initialized.

See [architecture](architecture.md) for entrypoints, panel-family loading and IPC, [config and common](config-and-common.md) for `Config`, `Persistent`, `Directories`, common models and widgets, [Hyprland](../hyprland.md) for the Lua configuration, and [dotfiles and theming](../dotfiles-and-theming.md) for the full theme scripts. UI composition belongs in [ii panels](panels-ii.md), [waffle panels](panels-waffle.md) and the [settings app](settings-app.md).

Path notation below:

- **S** = `dots/.config/quickshell/ii/services/`.
- **M** = `dots/.config/quickshell/ii/modules/`.
- **Q** = `dots/.config/quickshell/ii/`.
- Catalogue service filenames link to their actual source. Consumer paths are relative to **M**, except explicit `Q/` paths. Consumers are representative code references found with `rg`, not a complete dependency graph.
- Config column lists direct `Config.options.*` accesses in the service; braces group sibling keys. It does not include config read by its consumers or delegated scripts. “—” means no direct access.

| Key files | Role |
| --- | --- |
| [shell.qml](../../dots/.config/quickshell/ii/shell.qml) | Forces initialization of selected services at startup, lines 25–33. |
| [Ai.qml](../../dots/.config/quickshell/ii/services/Ai.qml), [ai/](../../dots/.config/quickshell/ii/services/ai/) | Chat orchestration, model/message types and wire-protocol strategies. |
| [KeyringStorage.qml](../../dots/.config/quickshell/ii/services/KeyringStorage.qml), [scripts/keyring/](../../dots/.config/quickshell/ii/scripts/keyring/) | One JSON secret stored through Secret Service. |
| [Notifications.qml](../../dots/.config/quickshell/ii/services/Notifications.qml) | Notification server, history, popup lifecycle and grouping. |
| [HyprlandConfig.qml](../../dots/.config/quickshell/ii/services/HyprlandConfig.qml), [hyprconfigurator.py](../../dots/.config/quickshell/ii/scripts/hyprland/hyprconfigurator.py) | Persistent shell-written Hyprland Lua overrides. |
| [MaterialThemeLoader.qml](../../dots/.config/quickshell/ii/services/MaterialThemeLoader.qml), [Wallpapers.qml](../../dots/.config/quickshell/ii/services/Wallpapers.qml) | Theme reload and wallpaper-script handoff. |
| [Network.qml](../../dots/.config/quickshell/ii/services/Network.qml), [network/WifiAccessPoint.qml](../../dots/.config/quickshell/ii/services/network/WifiAccessPoint.qml) | NetworkManager command wrapper and stable AP objects. |

## Structure and execution patterns

Services normally declare `pragma Singleton`, often `pragma ComponentBehavior: Bound`, and use Quickshell's `Singleton { id: root }` root. They import `qs.modules.common` for shared configuration/paths and `qs.modules.common.functions` for helpers. Consumers use `import qs.services`; service subfolders are imported as `qs.services.ai` and `qs.services.network`. The shell itself uses the relative directory import `import "services"` (`Q/shell.qml:10`). There is **no checked-in qmldir** in this tree: do not look for a hand-maintained export list to update. The `qs` import convention is used throughout the source; runtime import resolution is covered in [architecture](architecture.md).

Singletons initialize lazily. A reference from a loaded panel can initialize a service, but hidden/unloaded panels cannot be relied upon for startup side effects. `Q/shell.qml:25` explicitly calls `MaterialThemeLoader.reapplyTheme()`, `Hyprsunset.load()`, `FirstRunExperience.load()`, `ConflictKiller.load()`, `Cliphist.refresh()`, `Wallpapers.load()` and `Updates.load()`. Some `load()` methods are deliberately empty and only force initialization. Settings, welcome and conflict-dialog entrypoints each call `MaterialThemeLoader.reapplyTheme()` too.

Common I/O patterns:

- `Process` from `Quickshell.Io` owns a subprocess. Set `command: ["program", "arg", ...]` and `running = true`, or call `exec([...])`. Use `onExited(exitCode, exitStatus)` for completion. Examples: `S/Updates.qml:39`, `S/Network.qml:57`.
- `StdioCollector.onStreamFinished` receives complete output for JSON/text parsing; `SplitParser.onRead` handles streamed records. Examples: `S/HyprlandData.qml:99` versus long-running `nmcli monitor` in `S/Network.qml:163`. AI streams curl output through a strategy parser.
- `Quickshell.execDetached([...])` runs actions that do not need captured output. Pipelines, redirection and shell expansions explicitly use `["bash", "-c", "..."]` or `sh`. These are Bash commands even when the user's interactive shell is fish.
- `FileView` reads/writes JSON, watches generated files, or polls procfs. Loading is asynchronous unless configured otherwise; use loaded/error handlers. Notifications and Todo create empty files only on `FileViewError.FileNotFound`; they do not recover from arbitrary malformed JSON.
- Timers can poll continuously (`ResourceUsage`), debounce clipboard/theme changes (`Cliphist`, `MaterialThemeLoader`), or run only during an active task (`TimerService`). Check units: most QML intervals are milliseconds, update/weather config intervals are minutes, Pomodoro durations are seconds.
- `Quickshell.Hyprland` provides event connections, shortcuts, focus grabs and dispatch. Extra state is queried with `hyprctl ... -j`; do not assume all compositor state is exposed by a native Quickshell object.
- QObject-backed properties and ordinary JS arrays/maps have different notification behavior. Services often replace an array or shallow-clone a map to notify bindings (`S/Todo.qml:18`, `S/KeyringStorage.qml:34`). Preserve that step when modifying state.

## Service catalogue

### AI, content, search and persistence

| Service → purpose | Key public surface | Commands / dependencies | Direct config suffixes | Main consumers |
| --- | --- | --- | --- | --- |
| [Ai.qml](../../dots/.config/quickshell/ii/services/Ai.qml) → LLM chat/session manager | `models`, `currentModelId`, `messageIDs`, `messageByID`, `tokenCount`; `sendUserMessage`, `setModel`, `setTool`, `attachFile`, `saveChat/loadChat`, `approveCommand/rejectCommand`, `responseFinished` | Bash, curl; Ollama discovery script; Gemini uploads also file, jq, wc, grep/cut/tr; KeyringStorage | `ai.{systemPrompt,tool,extraModels}`, `policies.ai` | `ii/sidebarLeft/AiChat.qml`, `ii/sidebarLeft/aiChat/{AiMessage,MessageCodeBlock}.qml` |
| [AppSearch.qml](../../dots/.config/quickshell/ii/services/AppSearch.qml) → fuzzy app lookup and icon guessing | `list`, `fuzzyQuery`, `guessIcon`, `iconExists`, substitution maps | Quickshell DesktopEntries/icon lookup; common Fuzzy/Levendist | `search.sloppy` | `ii/dock/DockAppButton.qml`, `ii/overview/OverviewWindow.qml`, `waffle/looks/WIcons.qml` |
| [Booru.qml](../../dots/.config/quickshell/ii/services/Booru.qml) → provider-normalized image/tag searches | `providers/providerList`, `currentProvider`, `responses`, `runningRequests`; `makeRequest`, `setProvider`, `triggerTagSearch`, `tagSuggestion` | QML XMLHttpRequest; remote booru APIs; Persistent | `networking.userAgent`, `sidebar.booru.zerochan.username` | `ii/sidebarLeft/Anime.qml`, `ii/sidebarLeft/anime/BooruResponse.qml` |
| [BooruResponseData.qml](../../dots/.config/quickshell/ii/services/BooruResponseData.qml) → response record, **not singleton** | `provider`, `tags`, `page`, `images`, `message` | QtObject only | — | Created by `Booru`; exposed to Anime/BooruResponse UI |
| [Cliphist.qml](../../dots/.config/quickshell/ii/services/Cliphist.qml) → clipboard history/search/actions | `entries`, `fuzzyQuery`, `refresh`, `copy/paste`, `superpaste`, `deleteEntry`, `wipe` | cliphist (optional manually selected stash binary), wl-copy/wl-paste, ydotool, Bash | `search.sloppy`, `hacks.arbitraryRaceConditionDelay` | `LauncherSearch`; `common/widgets/CliphistImage.qml`, `ii/overview/SearchItem.qml`, `ii/sidebarLeft/AiChat.qml` |
| [Emojis.qml](../../dots/.config/quickshell/ii/services/Emojis.qml) → searchable emoji data from script | `list`, `fuzzyQuery`, `load`, `updateEmojis` | Reads `~/.config/hypr/hyprland/scripts/fuzzel-emoji.sh` after `### DATA ###`; Fuzzy | — | `LauncherSearch` (UI result generation) |
| [GoogleCloud.qml](../../dots/.config/quickshell/ii/services/GoogleCloud.qml) → service-account OAuth token lifecycle | `projectId`, `token`, `tokenExpiry`, `loaded`, key/token ready/error flags; `load`, `setKeyJson`, `unready` | KeyringStorage, MultiTurnProcess, `gCloud/token-from-key-venv.sh`, Python google-auth/requests, `ILLOGICAL_IMPULSE_VIRTUAL_ENV` | — | `common/models/gCloud/{GCloudTranslate,GCloudVision}.qml`, `ii/screenTranslator/ScreenTextOverlay.qml` |
| [KeyringStorage.qml](../../dots/.config/quickshell/ii/services/KeyringStorage.qml) → small JSON secret store | `loaded`, `keyringData`; `fetchKeyringData`, `saveKeyringData`, `setNestedField`, `dataChanged` | secret-tool, Secret Service; lookup/unlock scripts use busctl, gnome-keyring-daemon | — | `Ai`, `GoogleCloud`; `common/panels/lock/LockScreen.qml` |
| [LatexRenderer.qml](../../dots/.config/quickshell/ii/services/LatexRenderer.qml) → hash-cached formula SVGs | `requestRender(expression)` → [hash, isNew], `renderFinished(hash,path)`, `renderedImagePaths` | `/opt/MicroTeX/LaTeX` via Bash; Appearance colors/font | — | `ii/sidebarLeft/aiChat/MessageTextBlock.qml` |
| [LauncherApps.qml](../../dots/.config/quickshell/ii/services/LauncherApps.qml) → launcher pin ordering | `isPinned`, `togglePin`, `moveToFront/Left/Right` | Config only | `launcher.pinnedApps` | `waffle/startMenu/startPage/{StartAppButton,AppCategoryGrid}.qml`, `waffle/startMenu/searchPage/SearchResults.qml` |
| [LauncherSearch.qml](../../dots/.config/quickshell/ii/services/LauncherSearch.qml) → unified app, action, clipboard, emoji, calculator and web results | `query`, `results`, `appCategories`, `allActions`, `mathResult`, `ensurePrefix` | qalc, Bash, configured terminal/fish, notify-send; DesktopEntries, FolderListModel; executable user actions under `Directories.userActions`; wallpaper scripts | `apps.terminal`; `search.{engineBaseUrl,excludedSites,nonAppResultDelay}`; `search.prefix.{action,app,clipboard,emojis,math,shellCommand,webSearch,showDefaultActionsWithoutPrefix}`; `workSafety.enable.clipboard`, `workSafety.triggerCondition.{linkKeywords,networkNameKeywords}` | `ii/overview/{SearchWidget,SearchBar}.qml`, `waffle/startMenu/StartMenuContext.qml`, `waffle/startMenu/searchPage/SearchResults.qml` |
| [Notifications.qml](../../dots/.config/quickshell/ii/services/Notifications.qml) → notification daemon plus persistent history | `list/popupList`, `groupsByAppName`, `unread`, `silent`; `markAllRead`, `discardNotification`, `discardAllNotifications`, `timeoutAll`, `attemptInvokeAction` | Quickshell.Services.Notifications, FileView JSON | `notifications.timeout` | `common/widgets/Notification*.qml`, `ii/notificationPopup/NotificationPopup.qml`, `ii/sidebarRight/notifications/NotificationList.qml`, `waffle/notificationCenter/` |
| [TaskbarApps.qml](../../dots/.config/quickshell/ii/services/TaskbarApps.qml) → pinned/open app groups for taskbars | `apps` records: `appId,toplevels,pinned`; `isPinned`, `togglePin` | Wayland ToplevelManager; case-insensitive app grouping | `dock.{pinnedApps,ignoredAppRegexes}` | `ii/dock/{DockApps,DockAppButton}.qml`, `waffle/bar/tasks/{Tasks,TaskAppButton}.qml` |
| [Todo.qml](../../dots/.config/quickshell/ii/services/Todo.qml) → persistent task list | `list`, `filePath`; `addTask/addItem`, `markDone/markUnfinished`, `deleteItem`, `refresh` | FileView at `Directories.todoPath` | — | `ii/sidebarRight/todo/{TaskList,TodoWidget}.qml`, `ii/bar/ClockWidgetPopup.qml` |
| [Translation.qml](../../dots/.config/quickshell/ii/services/Translation.qml) → shell UI string localization | `tr`, `languageCode`, `translations/generatedTranslations`, `allAvailableLanguages`, `isScanning/isLoading` | find/basename; FileView; Qt locale | `language.ui` | Across both families and settings, e.g. `settings/ServicesConfig.qml`, `ii/bar/BarContent.qml`, `waffle/actionCenter/wifi/WifiControl.qml` |

### Desktop integration, hardware and session state

| Service → purpose | Key public surface | Commands / dependencies | Direct config suffixes | Main consumers |
| --- | --- | --- | --- | --- |
| [Audio.qml](../../dots/.config/quickshell/ii/services/Audio.qml) → PipeWire routing, levels and protection | `sink/source`, `value`, `ready`, device/app-node lists; `toggleMute/toggleMicMute`, volume steps, `setDefaultSink/Source`, `playSystemSound`, `sinkProtectionTriggered` | Quickshell.Services.Pipewire; ffplay and `/usr/share/sounds/<theme>/stereo/*.{oga,ogg}` | `audio.protection.{enable,maxAllowed,maxAllowedIncrease}`, `sounds.theme` | `ii/sidebarRight/volumeMixer/`, `ii/sidebarRight/QuickSliders.qml`, `waffle/actionCenter/volumeControl/`, OSDs |
| [Battery.qml](../../dots/.config/quickshell/ii/services/Battery.qml) → UPower state, threshold alerts and suspend | `available`, `percentage`, charge flags, low/critical/full flags, `health`, time/energy rate | Quickshell.Services.UPower, notify-send, systemctl/loginctl suspend; Audio sounds | `battery.{automaticSuspend,low,critical,suspend,full}`, `sounds.battery` | `ii/bar/{BatteryIndicator,BatteryPopup}.qml`, locks, `waffle/actionCenter/mainPage/MainPageFooter.qml` |
| [BluetoothStatus.qml](../../dots/.config/quickshell/ii/services/BluetoothStatus.qml) → sorted Bluetooth status/lists | `available/enabled/connected`, `firstActiveDevice`, `activeDeviceCount`, `friendlyDeviceList` | Quickshell.Bluetooth; native adapter/device objects | — | `ii/sidebarRight/bluetoothDevices/BluetoothDialog.qml`, `waffle/actionCenter/bluetooth/BluetoothControl.qml`, quick toggles |
| [Brightness.qml](../../dots/.config/quickshell/ii/services/Brightness.qml) → per-screen backlight/DDC brightness | `monitors`, `getMonitorForScreen`, `increase/decreaseBrightness`, `brightnessChanged`; monitor `brightness/ready/setBrightness` | brightnessctl, ddcutil; Hyprland focused monitor; anti-flash screenshots: grim, magick; Hyprsunset gamma | `light.antiFlashbang.enable` | `ii/sidebarRight/QuickSliders.qml`, `ii/onScreenDisplay/indicators/BrightnessIndicator.qml`, `waffle/actionCenter/mainPage/MainPageBodySliders.qml` |
| [ConflictKiller.qml](../../dots/.config/quickshell/ii/services/ConflictKiller.qml) → detect competing tray/notification daemons | `load`, `killDialogQmlPath` | Bash, pidof kded6/mako/dunst, killall, qs `killDialog.qml` | `conflictKiller.{autoKillTrays,autoKillNotificationDaemons}` | `Q/shell.qml` startup |
| [DateTime.qml](../../dots/.config/quickshell/ii/services/DateTime.qml) → formatted clock/date/uptime | `clock`, `time`, `shortDate/date/longDate`, `collapsedCalendarFormat`, `uptime` | SystemClock, Qt locale, FileView `/proc/uptime` | `time.{secondPrecision,format,shortDateFormat,dateWithYearFormat,dateFormat}`, `resources.updateInterval` | ii clock/calendar/lock widgets; `waffle/bar/TimeButton.qml`, `waffle/notificationCenter/DateHeader.qml` |
| [EasyEffects.qml](../../dots/.config/quickshell/ii/services/EasyEffects.qml) → EasyEffects availability/start/stop | `available/active`, `fetchAvailability/fetchActiveState`, `enable/disable/toggle` | easyeffects or Flatpak `com.github.wwmm.easyeffects`; pidof/pkill | — | `common/models/quickToggles/EasyEffectsToggle.qml`, classic toggle, `waffle/actionCenter/volumeControl/VolumeControl.qml` |
| [FirstRunExperience.qml](../../dots/.config/quickshell/ii/services/FirstRunExperience.qml) → first-run marker and welcome launch | `load`, `enableNextTime/disableNextTime`, `handleFirstRun` | FileView; rm/Bash; wallpaper switch script; qs `welcome.qml` | — | `Q/shell.qml` startup |
| [GlobalFocusGrab.qml](../../dots/.config/quickshell/ii/services/GlobalFocusGrab.qml) → shared dismissal/focus-grab set | `persistent/dismissable`, add/remove methods, `dismiss`, `dismissed` | HyprlandFocusGrab; recursive active-focus inspection | — | ii bar, sidebars, overview, cheatsheet, OSK, media controls and wallpaper selector |
| [HyprlandAntiFlashbangShader.qml](../../dots/.config/quickshell/ii/services/HyprlandAntiFlashbangShader.qml) → compositor screen-shader switch | `enabled/weak`, `enable/enableWeak/disable/toggle/cycle` | HyprlandConfig + HyprlandConfigOption; bundled GLSL files | — | `common/models/quickToggles/AntiFlashbangToggle.qml`, `ii/sidebarRight/nightLight/NightLightDialog.qml` |
| [HyprlandConfig.qml](../../dots/.config/quickshell/ii/services/HyprlandConfig.qml) → persistent Lua overrides | `set/setMany/reset/resetMany`, `reloaded`, `shellOverridesPath` | Bash, `scripts/hyprland/hyprconfigurator.py`; Hyprland raw events | — | `common/models/hyprland/HyprlandConfigOption.qml`, `common/models/quickToggles/GameModeToggle.qml`; shader service |
| [HyprlandData.qml](../../dots/.config/quickshell/ii/services/HyprlandData.qml) → supplemental compositor JSON state | `windowList/windowByAddress`, `workspaces/workspaceById`, `activeWorkspace`, `monitors/layers`; workspace/toplevel helpers, `updateAll` | `hyprctl {clients,monitors,layers,workspaces,activeworkspace} -j`; Hyprland events; ToplevelManager | — | `common/models/WorkspaceModel.qml`, ii overview/background/region-selector, `waffle/taskView/` |
| [HyprlandKeybinds.qml](../../dots/.config/quickshell/ii/services/HyprlandKeybinds.qml) → described runtime binds for cheatsheet | `keybinds`, `keybindCategories` | `hyprctl binds -j`; configreloaded event | — | `ii/cheatsheet/{CheatsheetKeybinds,CheatsheetKeybindsCategory}.qml` |
| [HyprlandXkb.qml](../../dots/.config/quickshell/ii/services/HyprlandXkb.qml) → active keyboard layout name/code | `layoutCodes`, `currentLayoutName/Code`, cache | `hyprctl -j devices`, cat `/usr/share/X11/xkb/rules/base.lst`; activelayout/configreloaded | Reads no config key; writes `osk.layout` | `ii/bar/HyprlandXkbIndicator.qml`, `ii/lock/LockSurface.qml` |
| [Hyprsunset.qml](../../dots/.config/quickshell/ii/services/Hyprsunset.qml) → night temperature schedule and gamma | `temperatureActive`, `automatic`, `gamma`, `load`, `toggleTemperature`, `setGamma`, `fetchState`, `gammaChangeAttempt` | hyprsunset, pidof, `hyprctl hyprsunset {temperature,gamma}`; DateTime | `light.night.{from,to,automatic,colorTemperature}` | night-light toggles/dialogs in both families; ii brightness/gamma OSD; Brightness service |
| [Idle.qml](../../dots/.config/quickshell/ii/services/Idle.qml) → persistent idle inhibition | `inhibit`, `toggleInhibit` | Wayland IdleInhibitor on zero-size transparent PanelWindow; Persistent idle state | — | `common/models/quickToggles/IdleInhibitorToggle.qml`, `common/panels/lock/LockScreen.qml` |
| [MaterialThemeLoader.qml](../../dots/.config/quickshell/ii/services/MaterialThemeLoader.qml) → watch generated Material palette | `filePath`, `reapplyTheme`, `applyColors`, `toggleLightDark` | FileView, Appearance; wallpaper switch script; shortcut/IPC | `hacks.arbitraryRaceConditionDelay`; observes `background.wallpaperPath` | `Q/{shell,settings,welcome,killDialog}.qml`; Appearance propagates to widgets |
| [MprisController.qml](../../dots/.config/quickshell/ii/services/MprisController.qml) → active media-player controls | `players/activePlayer/activeTrack`, `isPlaying`, `togglePlaying`, `previous/next`, `setActivePlayer`, loop/shuffle setters, `trackChanged` | Quickshell.Services.Mpris, D-Bus; optional plasma-browser-integration filtering | `media.filterDuplicatePlayers` | `ii/bar/Media.qml`, `ii/mediaControls/MediaControls.qml`, `waffle/actionCenter/MediaPaneContent.qml` |
| [Network.qml](../../dots/.config/quickshell/ii/services/Network.qml) → Wi-Fi/Ethernet status/control | `wifiEnabled`, `wifiStatus`, `wifiNetworks`, `active`, `friendlyWifiNetworks`, `ethernet`, `networkName`, `materialSymbol`; Wi-Fi control methods | nmcli/NetworkManager; Bash/sh, head/awk; xdg-open captive-portal URL | — | `ii/sidebarRight/wifiNetworks/`, `waffle/actionCenter/wifi/`, NetworkToggle, bars |
| [PolkitService.qml](../../dots/.config/quickshell/ii/services/PolkitService.qml) → authentication agent/flow | `agent/active/flow`, `interactionAvailable`, `cleanMessage/cleanPrompt`, `submit/cancel` | Quickshell.Services.Polkit | — | `ii/polkit/PolkitContent.qml`, `waffle/polkit/WPolkitContent.qml`, `common/widgets/FullscreenPolkitWindow.qml` |
| [Privacy.qml](../../dots/.config/quickshell/ii/services/Privacy.qml) → intended screen/mic activity flags | `screenSharing`, `micActive` | Pipewire linkGroups/PwNodeType | — | No direct `Privacy.*` module consumer found; see gotcha below |
| [ResourceUsage.qml](../../dots/.config/quickshell/ii/services/ResourceUsage.qml) → RAM/swap/CPU polling and histories | totals/used/percentages, `cpuUsage`, history arrays, max-capacity strings | FileView `/proc/{meminfo,stat}`; lscpu/grep/awk | `resources.{historyLength,updateInterval}` | `ii/bar/{Resources,ResourcesPopup}.qml`, vertical bar, overlay resources |
| [SessionWarnings.qml](../../dots/.config/quickshell/ii/services/SessionWarnings.qml) → heuristic unsafe-to-exit indicators | `packageManagerRunning/downloadRunning`, `refresh` | pidof package managers/downloaders; `/var/lib/pacman/db.lck`; `~/Downloads/*.{crdownload,part}` via ls/grep | — | `ii/sessionScreen/SessionScreen.qml`, `waffle/sessionScreen/WaffleSessionScreen.qml` |
| [SongRec.qml](../../dots/.config/quickshell/ii/services/SongRec.qml) → music recognition task | `running`, `recognizedTrack`, `monitorSource`, `toggleRunning`, `toggleMonitorSource` | `scripts/musicRecognition/recognize-music.sh`: songrec, pactl, FIFO; notify-send actions/browser URLs | `musicRecognition.{interval,timeout}` | `common/models/quickToggles/MusicRecognitionToggle.qml`, `ii/overview/SearchBar.qml` |
| [SystemInfo.qml](../../dots/.config/quickshell/ii/services/SystemInfo.qml) → distro/user/session metadata | `distroName/Id/Icon`, `username`, distro URLs, `desktopEnvironment/windowingSystem` | FileView `/etc/os-release`, whoami, Bash environment `XDG_CURRENT_DESKTOP/WAYLAND_DISPLAY` | — | `settings/About.qml`, common Directories, locks, AI message UI, waffle user button |
| [TimerService.qml](../../dots/.config/quickshell/ii/services/TimerService.qml) → Pomodoro/stopwatch state | `pomodoroRunning`, `pomodoroSecondsLeft`, `pomodoroCycle`, `stopwatchRunning`, `stopwatchTime`, `stopwatchLaps`; toggle/reset methods, lap recording | Timers, Persistent timer state, notify-send; Audio | `time.pomodoro.{focus,breakTime,longBreak,cyclesBeforeLongBreak}`, `sounds.pomodoro` | `ii/sidebarRight/pomodoro/`, `waffle/notificationCenter/FocusFooter.qml` |
| [TrayService.qml](../../dots/.config/quickshell/ii/services/TrayService.qml) → filtered/pinned status-notifier items | `pinnedItems/unpinnedItems`, `pin/unpin/togglePin/isPinned`, `getTooltipForItem` | Quickshell.Services.SystemTray | `tray.{filterPassive,invertPinnedItems,pinnedItems,showItemId}` | `ii/bar/{SysTray,SysTrayItem,SysTrayMenu}.qml`, `waffle/bar/tray/` |
| [Updates.qml](../../dots/.config/quickshell/ii/services/Updates.qml) → Arch update count | `available/checking/count`, `updateAdvised/updateStronglyAdvised`, `load/refresh` | which, `checkupdates | wc -l`, Bash | `updates.{enableCheck,checkInterval,adviseUpdateThreshold,stronglyAdviseUpdateThreshold}` | `Q/shell.qml`, `waffle/bar/UpdatesButton.qml` |
| [Wallpapers.qml](../../dots/.config/quickshell/ii/services/Wallpapers.qml) → wallpaper browser/apply/thumbnails | `directory/folderModel/wallpapers/searchQuery`, `select/apply`, directory navigation, `generateThumbnail`, progress/signals | wallpaper switch script; test/Bash; thumbnail Python venv wrapper with ImageMagick script fallback | — | `ii/wallpaperSelector/{WallpaperSelector,WallpaperSelectorContent}.qml` |
| [Weather.qml](../../dots/.config/quickshell/ii/services/Weather.qml) → current weather and optional positioning | `data`, `city`, `location`, `gpsActive`, `getData/refineData` | curl wttr.in, jq; QtPositioning backend; notify-send fallback | `bar.weather.{fetchInterval,city,useUSCS,enableGPS}` | `ii/bar/weather/{WeatherBar,WeatherPopup}.qml`, `ii/background/widgets/weather/WeatherWidget.qml` |
| [Ydotool.qml](../../dots/.config/quickshell/ii/services/Ydotool.qml) → OSK synthetic key events | `shiftMode`, modifier keycode lists; `press/release`, `releaseAllKeys/releaseShiftKeys` | ydotool (working daemon/input permissions required externally) | — | `ii/onScreenKeyboard/{OnScreenKeyboard,OskKey}.qml` |
| [T3.qml](../../dots/.config/quickshell/ii/services/T3.qml) → T3 Code threads for the left sidebar (read-only) | `online`, `error`, `environmentId`, `projects`, `threads` (`t3/T3Thread`), `pinned/active/snoozed/settledThreads`, `attentionCount`, `tokenCommand`; `openThread`, `newThread`, `launch` | Runs `scripts/t3/t3-sidebar-bridge.mjs` (Node ≥ 22) against the T3 desktop server; `xdg-open t3code://…`, `~/.t3/bin/t3 app`, `gtk-launch` | `sidebar.t3.tokenFile` | `ii/sidebarLeft/SidebarLeftContent.qml`, `ii/bar/LeftSidebarButton.qml`. See [t3-sidebar.md](t3-sidebar.md) |

### Subfolder support files

These are implementation helpers, not additional global singleton services.

| File | Contract / dependency |
| --- | --- |
| [ai/AiModel.qml](../../dots/.config/quickshell/ii/services/ai/AiModel.qml) | Model metadata QObject: endpoint/model, display metadata, `requires_key/key_id`, `api_format`, `tools`, `extraParams`. |
| [ai/AiMessageData.qml](../../dots/.config/quickshell/ii/services/ai/AiMessageData.qml) | Message QObject: role/content/rawContent, completion/thinking, file metadata, citations/search queries, function-call/pending/response fields. |
| [ai/ApiStrategy.qml](../../dots/.config/quickshell/ii/services/ai/ApiStrategy.qml) | Abstract QObject methods for endpoint/auth/request generation, stream parsing, finish/reset and attachment script hooks. |
| [ai/GeminiApiStrategy.qml](../../dots/.config/quickshell/ii/services/ai/GeminiApiStrategy.qml) | Gemini contents/parts, buffered JSON stream, grounding/citations, function calls and resumable file uploads. |
| [ai/OpenAiApiStrategy.qml](../../dots/.config/quickshell/ii/services/ai/OpenAiApiStrategy.qml) | Chat-completions request + SSE text/reasoning/usage parser; used by local Ollama models too. |
| [ai/MistralApiStrategy.qml](../../dots/.config/quickshell/ii/services/ai/MistralApiStrategy.qml) | Chat-completions variant with tool-call parsing and tool-response formatting. |
| [network/WifiAccessPoint.qml](../../dots/.config/quickshell/ii/services/network/WifiAccessPoint.qml) | QObject wrapper over required `lastIpcObject`: readonly ssid/bssid/strength/frequency/active/security/isSecure, mutable `askingPassword`. |
| [gCloud/token-from-key-venv.sh](../../dots/.config/quickshell/ii/services/gCloud/token-from-key-venv.sh), [token_from_key.py](../../dots/.config/quickshell/ii/services/gCloud/token_from_key.py) | Activate configured venv; google-auth service-account credentials with cloud-platform scope; output JSON `token,expiry` (epoch seconds). No direct Config keys. |
| [hyprlandAntiFlashbangShader/anti-flashbang.glsl](../../dots/.config/quickshell/ii/services/hyprlandAntiFlashbangShader/anti-flashbang.glsl), [anti-flashbang-weak.glsl](../../dots/.config/quickshell/ii/services/hyprlandAntiFlashbangShader/anti-flashbang-weak.glsl) | GLES 3 shaders sample a 10×10 grid, compute weighted brightness, blend black with opacity brightness×0.75 or ×0.42. No Config reads; selected by shader service. |

## AI: providers, secrets, requests and tools

### Models and strategies

`S/Ai.qml:257` currently declares Gemini 2.5 Flash, Gemini 3 Flash (the endpoint/model is `gemini-3-flash-preview`) and Mistral Medium 3. OpenAI-compatible support exists as a strategy, rather than a built-in OpenAI model entry. `Config.options.ai.extraModels` is merged at initialization and when Config becomes ready (`S/Ai.qml:308`). A model ID is derived from `model` by replacing colons with underscores, spaces/slashes with hyphens; model selection lowercases its argument.

`scripts/ai/show-installed-ollama-models.sh` runs `ollama list`, extracts model names and prints JSON. The startup process in `S/Ai.qml:358` creates keyless models at `http://localhost:11434/v1/chat/completions` with the default `openai` strategy. It discovers installed models; it does not start an Ollama server.

Policy `policies.ai === 2` suppresses built-in online entries. `setModel()` rejects endpoints whose string does not contain `localhost` under that policy (`S/Ai.qml:486`). This is the implementation's string check, not a general network-isolation mechanism.

Each `ApiStrategy` builds a request object and interprets response lines. Gemini uses `contents`, `system_instruction` and `generationConfig`; OpenAI/Mistral use `messages`, `model`, `stream` and `temperature`. All three shallow-merge `extraParams` **after** the base request, allowing replacement of generated fields. The requester captures the chosen strategy for the active request (`S/Ai.qml:580`).

Capabilities differ:

- Gemini parses streamed JSON, grounding sources/supports, search queries, usage, and the first returned function-call part (`S/ai/GeminiApiStrategy.qml:100`). It uploads attachments using the Files API before chat, detects MIME with `file`, uses jq for URI extraction, and adds file metadata to messages (`:199`).
- OpenAI parses SSE `data:` lines, `[DONE]`, text, reasoning and usage. It sends a tools field but **does not parse tool_calls** and ignores the attachment argument (`S/ai/OpenAiApiStrategy.qml:11`, `:34`). Do not advertise full OpenAI function/file support based on the shared interface.
- Mistral has a `tool_calls[0]` branch (`S/ai/MistralApiStrategy.qml:76`). It parses arguments as complete JSON immediately; fragmented tool-call deltas are not accumulated. End-to-end tool roundtrips are unverified. The old comment “functions only work with Gemini” at `S/Ai.qml:16` predates this branch.

### Request and chat lifecycle

`sendUserMessage()` adds a user `AiMessageData` then invokes the requester. Messages are held as ordered `messageIDs` plus `messageByID`; interface/help messages have role `interface` and are excluded from API requests (`S/Ai.qml:452`, `:596`). Raw and display content are retained separately; reasoning is wrapped in `<think>` blocks by the compatible strategies.

The requester writes `/tmp/quickshell/ai/request.sh` using FileView, then runs it with Bash. It uses curl `--no-buffer`, puts the selected key in the child environment as `API_KEY`, and supplies the strategy's auth syntax. Gemini expands it in a URL query parameter; OpenAI/Mistral expand a Bearer header. Stream parsing updates the message object and token counts. Completion sets `done`, runs any one-shot hook, saves `lastSession`, and emits `responseFinished` (`S/Ai.qml:586`).

`saveChat/loadChat` use JSON files under `Directories.aiChats` = `Directories.state/user/ai/chats` (`S/Ai.qml:835`; `M/common/Directories.qml:48`). The save includes interface messages, raw content, attachments and function metadata. It is not encrypted secret storage. `printApiKey()` puts the actual key into a chat message (`:550`), which can therefore enter a saved chat.

### Key storage and unlock

`Ai.apiKeys` is `KeyringStorage.keyringData.apiKeys`; `setApiKey()` stores at `["apiKeys", model.key_id]` (`S/Ai.qml:535`). Models sharing a key should share `key_id`.

`S/KeyringStorage.qml:75` stores the **entire JSON object** through `secret-tool store`, sending it on stdin and closing stdin after writing. Attributes include `application=illogical-impulse` and a translated explanation; lookup uses the application attribute. The label is translated “illogical-impulse Safe Storage”. This is a small-data store, not a per-key database.

`scripts/keyring/try_lookup.sh` calls `secret-tool lookup`; if empty, `is_unlocked.sh` queries the login collection's `Locked` property using busctl. Exit 1 means no entry and causes empty-store initialization; exit 2 means locked and leaves `loaded` false (`S/KeyringStorage.qml:91`). No lookup runs automatically inside KeyringStorage itself: callers fetch when needed. Lock-screen code runs `unlock.sh` and fetches again (`M/common/panels/lock/LockScreen.qml:34`, `:138`). The unlock script uses `UNLOCK_PASSWORD` or an interactive prompt and restarts the user's gnome-keyring-daemon.

GoogleCloud shares this JSON under `googleCloud.serviceAccountKey`. `setKeyJson()` validates JSON syntax, not credentials. `loadKeyIfPossible()` listens for loaded/data changes, extracts project ID, and asks the Python helper for a token. `load()` refreshes an already-ready token when expired; there is no periodic renewal timer (`S/GoogleCloud.qml:24`, `:83`).

### Tools and approval boundary

`Ai.tools[api_format][currentTool]` selects `functions`, `search` or `none` (`S/Ai.qml:84`). Only Gemini's search list contains a web-search tool; compatible strategies' search lists are empty.

`handleFunctionCall()` implements (`S/Ai.qml:803`):

- `get_shell_config`: serialize Config options, append a function-output message, request another turn.
- `set_shell_config`: call `Config.setNestedValue(key,value)` directly. It is **not** routed through the command-approval UI, and the “get first” rule lives in tool description text.
- `run_shell_command`: append a command request and mark the message `functionPending`. `approveCommand()` executes Bash, streams stdout into a function-output message, appends exit information, then requests another turn. `rejectCommand()` records rejection (`:762`). UI buttons are in `M/ii/sidebarLeft/aiChat/AiMessage.qml`.
- Gemini-only `switch_to_search_mode`: temporarily switch tools to search, request continuation, restore functions in a post-response hook.

### Adding a model, provider or prompt

1. For another model using an existing wire protocol, add an object to `ai.extraModels` using fields in `S/ai/AiModel.qml:18`: `name,icon,description,endpoint,model,requires_key,key_id,key_get_link,key_get_description,api_format,extraParams`. Set `requires_key: false` for keyless endpoints. Use `api_format: "openai"` only for this chat-completions format; other API formats need a strategy.
2. To ship a default, add an `aiModelComponent.createObject` entry to `Ai.models`. Preserve the policy gate. Ensure the derived/custom model ID and lowercased selection agree; reuse `key_id` for shared credentials.
3. For a new protocol, implement the `ApiStrategy.qml` methods, register its Component and instance in `Ai.qml:21` and `:301`, and define its tool-mode table. Parse streaming boundaries, errors and usage; return `functionCall`, `tokenUsage` and/or `finished` as the requester expects. Implement file setup/finalization only if that provider supports it.
4. Check plain text, reasoning, streaming completion, malformed/error responses, keyless/keyed behavior, chat save/load, and any supported tool/file roundtrip. Existing strategies are not proof that a different provider accepts the same payload.
5. Bundled prompts are `Q/defaults/ai/prompts/*.{md,txt}`; user prompts are `Directories.shellConfig/ai/prompts`. Both lists are scanned once at service init with ls (`S/Ai.qml:390`). `loadPrompt()` writes the file text into `Config.options.ai.systemPrompt`; substitutions `{DISTRO},{DATETIME},{WINDOWCLASS},{DE}` happen in the service binding (`:31`, `:74`). Prompt provenance is in `Q/defaults/ai/README.md`.

The standalone AI scripts are separate consumers of the same stored Gemini key: `scripts/ai/gemini-categorize-wallpaper.sh` resizes with magick, base64-encodes an image, asks for an enum category; `gemini-translate.sh` updates source translation keys, requests a JSON translation, writes it under the user's shell config, and changes `language.ui` with jq. These do not go through the chat service or its selected model.

## Notifications: daemon, popups and persistence

`S/Notifications.qml:150` owns the Quickshell NotificationServer with actions, markup, images, hyperlinks and persistence support; `keepOnReload: false`. Every received notification is tracked and wrapped in a `Notif` QObject with app/body/image/action/time/urgency data. The wrapper retains a live server object for actions and dismissals.

History `list` and popup visibility are separate. `popupList` filters `popup=true`; grouping maps and app-name lists sort by each application's latest notification timestamp (`:96`). `popupInhibited` is `GlobalStates.sidebarRightOpen` OR `silent` (`:81`). Receipt always appends/persists/emits notify; only uninhibited receipt marks popup and increments unread (`:162`). `sidebarRightOpen` is shared, so waffle's notification center (`WaffleNotificationCenter.qml`) inhibits popups too.

For nonzero expireTimeout, a per-notification Timer removes transient notifications entirely or just hides normal popups. Negative timeout uses `notifications.timeout` (fallback 7000 ms); zero creates no timer (`:61`, `:174`). Discard removes history, saves JSON, dismisses the live server object and emits a signal. Timeout hides the popup without dropping history. `markAllRead()` only resets unread.

Persistence uses `Directories.notificationsPath` = `Directories.cache/notifications/notifications.json` (`M/common/Directories.qml:39`). The serialized fields omit live objects, timers, popup/transient state and unread. Startup reloads records with **empty actions**, computes the maximum stored ID, and offsets new server IDs by that amount (`S/Notifications.qml:267`). Saved notifications are display history, not actionable reconnections to the original sender. Missing file creates an empty list; JSON parsing in `onLoaded` has no try/catch.

When changing notifications, inspect both common notification widgets and family-specific popup/center components; their animation hooks use `notify,discard,discardAll,timeout,initDone`. Do not replace IDs with array indices or conflate “hide popup” with “dismiss”.

## Hyprland state, cheatsheet and Lua config

### Supplemental state

`S/HyprlandData.qml:79` queries clients, monitors, layers, workspaces and activeworkspace at initialization. Most raw Hyprland events rerun all queries; `openlayer,closelayer,screencast` are explicitly ignored (`:87`). Thus the presence of an event stream does not mean layer state is refreshed on every layer change. Parsed windows are indexed by `0x...` address, workspaces by ID; workspace lists exclude IDs outside 1–100 (`:139`).

Helpers join native Wayland toplevels to Hyprland JSON using `0x${toplevel.HyprlandToplevel.address}`. Preserve this address representation in overview/workspace/region-selector changes. `clientForToplevel`, `toplevelsForWorkspace`, `hyprlandClientsForWorkspace` and `biggestWindowForWorkspace` avoid repeating joins.

### Cheatsheet

The actual source is **runtime `hyprctl binds -j`**, not a parser walking Lua/config files. `S/HyprlandKeybinds.qml:31` queries at init and on `configreloaded`. It records the JSON and derives distinct nonempty category prefixes before the first colon in each `description`. Its header mentioning `get_keybinds.py` is stale.

Lua bindings specify descriptions, e.g. `dots/.config/hypr/hyprland/keybinds.lua:31` uses `{ description = "Shell: Toggle cheatsheet" }`. Give new binds `"Category: Action"` descriptions for the cheatsheet. Bindings with no description are filtered from the UI; described bindings without a colon go to “Uncategorized”.

Presentation lives in `M/ii/cheatsheet/CheatsheetKeybinds.qml:30` and `CheatsheetKeybindsCategory.qml:115`. It decodes modmask, applies configurable key symbols, drops repetitive numeric bindings beyond 1 and right/up/down variants, and renders 1/Left as generic number/direction. A missing cheatsheet entry may be a presentation filter rather than a missing compositor bind. See [ii panels](panels-ii.md).

### Read/write configuration path

`S/HyprlandConfig.qml:19` writes `~/.config/hypr/hyprland/shellOverrides/main.lua` through `Q/scripts/hyprland/hyprconfigurator.py`. APIs take colon-separated option keys (`decoration:screen_shader`, etc.) and expose single/batch set/reset. They do not edit the user's custom Lua or legacy `hyprland.conf`.

The configurator builds nested Lua, e.g. `hl.config({decoration={screen_shader="..."}})`, from a colon-separated key (`scripts/hyprland/hyprconfigurator.py:17`). It replaces/removes matching one-line entries or appends them, preserves unrelated lines, and atomically replaces the file using a temp file in the same directory (`:30`, `:88`). `[[EMPTY]]` means reset. This is a targeted line editor, not a general Lua parser; keep the generated override file in its expected one-setting-per-line form. The script's default .conf argument is stale, but the QML service always passes the Lua path.

`dots/.config/hypr/hyprland.lua:44` requires `hyprland.shellOverrides.main` after the normal/custom configs. The service listens for compositor `configreloaded` and emits `reloaded()`; it does not explicitly run hyprctl reload. Native compositor reload behavior is a runtime dependency, unverified here.

Reading an option is the common model `M/common/models/hyprland/HyprlandConfigOption.qml:38`: `hyprctl getoption -j <key>`, expose `value/set/fetching`, and refetch after `HyprlandConfig.reloaded`. See [config and common](config-and-common.md). Write through the service, read through that model rather than parsing arbitrary Lua.

The shader service uses this path to set `decoration:screen_shader` and `debug:damage_tracking=1`, cycling off → weak → strong → off. Disabling resets both keys (`S/HyprlandAntiFlashbangShader.qml:17`). This is distinct from Brightness's `light.antiFlashbang.enable` mechanism, which takes screenshots and adjusts hardware brightness multipliers.

## Wallpaper and theme handoff

`S/Wallpapers.qml:36` is a limited file browser plus script launcher. It exposes a `FolderListModelWithHistory`, defaults to Pictures/Wallpapers, includes readable directories and common image extensions, and supports navigation/search. `select()` first tests whether the path is a directory; directories navigate, files call `apply()`. `apply()` starts `Directories.wallpaperSwitchScriptPath --mode dark|light --image <path>` and emits `changed()` immediately (`:42`), without waiting for script success.

The external pipeline is `Q/scripts/colors/switchwall.sh` → matugen + material color generation → `applycolor.sh` (`switchwall.sh:306`). It also updates `background.wallpaperPath` in the shell config (`:147`). Matugen's `templates.m3colors` writes `~/.local/state/quickshell/user/generated/colors.json` (`dots/.config/matugen/config.toml:4`). The shell-side hook is `MaterialThemeLoader`, not a QML palette generator.

`S/MaterialThemeLoader.qml:23` parses that JSON, converts snake_case keys to camel case prefixed with `m3`, assigns them into `Appearance.m3colors`, then infers dark mode from background HSL lightness < 0.5. A watched FileView reloads on change, with a delayed read using `hacks.arbitraryRaceConditionDelay` (`:52`). Failure arms a one-shot reset of the watched path on the next wallpaperPath change. Startup `reapplyTheme()` is required because this singleton is lazy.

Both `toggleLightDark()` and theme IPC/shortcut call switchwall with `--noswitch`, changing the theme without selecting another wallpaper. Wallpaper IPC target is `wallpapers`, theme IPC target is `theme`. Full script behavior and application theming belong in [dotfiles and theming](../dotfiles-and-theming.md).

Thumbnail generation accepts only `normal,large,x-large,xx-large`, runs the venv thumbnail wrapper with ImageMagick fallback, and parses `PROGRESS n/total` and `FILE path` stdout (`S/Wallpapers.qml:136`). UI should use progress/file/completion signals; directory listings may contain directories as well as images.

## Network and audio

### NetworkManager

`S/Network.qml` has no direct Config dependency. Initialization queries connection type/connectivity, active connection name, signal, radio state and APs; a persistent `nmcli monitor` process triggers status updates (`:156`). AP refreshes also follow rescan/connect/disconnect output. There is no periodic polling timer or monitor-process restart loop.

`getNetworks` requests colon-separated `ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY`, protects escaped colons during splitting, then groups by SSID, preferring the active AP or strongest inactive AP (`:259`). It preserves wrapper identities when frequency/SSID/BSSID match by replacing `lastIpcObject`; vanished wrappers are destroyed. `friendlyWifiNetworks` sorts active first, then signal. UI password prompts belong to `WifiAccessPoint.askingPassword`, so do not replace wrappers indiscriminately.

`connectToWifiNetwork()` runs `nmcli dev wifi connect <ssid>`, creating a profile if necessary. stderr “Secrets were required” and unsuccessful exit enable the prompt. `changePassword()` supplies SSID/password in environment variables, runs `nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"`, then restarts connection (`:71`, `:87`). Enterprise Wi-Fi username handling is explicitly TODO; the method's username argument is unused. Disconnect targets the active SSID. Captive portal opens `https://nmcheck.gnome.org/`.

Several parsing processes force `LANG/LC_ALL=C`, but not every nmcli query does. The service assumes textual command output and NetworkManager availability; do not treat it as a generic network backend. ii and waffle have separate Wi-Fi controls over this same singleton.

### PipeWire

`S/Audio.qml:15` binds native default sink/source, tracks them with PwObjectTracker and filters native nodes into device/stream lists. Set `sink.audio.volume` or `muted` for control; default routing uses `Pipewire.preferredDefaultAudioSink/Source`. The service does not shell out to pactl/wpctl for normal mixer operations.

Volume is normalized (1 = 100%). Increment/decrement use 0.01 below 10%, otherwise 0.02; increment caps at 1. The protection connection watches sink volume, initializes its prior sample without writing, rejects increases larger than `maxAllowedIncrease/100`, and limits `maxAllowed/100` plus hard cap 2 (`:84`). It emits `sinkProtectionTriggered(reason)` for the OSD. Guard unavailable sink/source in new consumers; these controls themselves do not all null-check.

`playSystemSound()` starts ffplay for both .oga and .ogg variants of the sound name; it is not conditional on general sound preferences (`:117`). Callers such as Battery and TimerService apply their own enable options.

## Booru, localization and weather

### Booru provider contract

`S/Booru.qml:24` defines yandere, konachan, zerochan, danbooru, gelbooru, waifu.im and t.alcy.cc. Provider entries include display/url/API information plus a `mapFunc` (JSON APIs) or `manualParseFunc` (Alcy newline image URLs). Mappers normalize IDs/dimensions/aspect ratio/tags/rating/NSFW/preview/sample/file/source. `currentProvider` is stored in `Persistent.states.booru.provider`.

`constructRequestUrl()` implements provider-specific tags, safe-rating filters, limits and page conventions (`:309`). Zerochan uses color, not a normal tag search, and its configured username customizes the User-Agent. Some providers use the general configured User-Agent. A new provider usually needs an entry, response mapping, URL-construction branch if its query differs, and optional `tagSearchTemplate/tagMapFunc` or `fixedTags`.

Requests use XMLHttpRequest, not curl. Completed results append `BooruResponseData` and decrement `runningRequests`; failures produce a system-readable fail message (`:360`). `responseFinished` is called from onreadystatechange without a DONE-only guard; do not assume one emission per request. The response callback reads `providers[currentProvider]` at callback time, so provider changes during in-flight requests deserve care. Tag search cancels the previous request and emits normalized suggestions (`:424`). Download/display UI lives in `M/ii/sidebarLeft/anime/`; do not put panel rendering in the provider service.

### Translation

`Translation` localizes **shell UI strings**, not selected-text/network translation. Built-in JSON lives in `Q/translations/<locale>.json`; generated JSON in `~/.config/illogical-impulse/translations/<locale>.json`. `language.ui="auto"` uses `Qt.locale().name` (`S/Translation.qml:25`). Startup scanners enumerate JSON basenames with find; language changes reset reader paths and reload both sources.

`tr(text)` returns empty for empty input, original text for missing keys/loading, then built-in value before generated value before original. A trailing `/*keep*/` is stripped (`:78`). Add UI strings with `Translation.tr("source key")`; source text is the lookup key, so changing it also changes the translation key. Generated translations fill gaps rather than overriding shipped nonempty entries. Reader failures return an empty dictionary; scanners run at initialization, so a newly created locale may require service/shell reload to appear in language lists.

The separate Gemini translation generator is described above; selected-text/screen translation uses GoogleCloud-backed common models and panel code. See [ii panels](panels-ii.md).

### Weather

`S/Weather.qml:83` builds a curl request to `wttr.in/<city>?format=j1`, or coordinates when GPS is active/valid, and jq narrows it to current conditions, nearest area and today's astronomy. `refineData()` formats strings and USCS/metric units into `data`, stamping refresh with DateTime (`:49`). These are formatted UI values, not a typed meteorological model.

QtPositioning PositionSource uses the same minute-derived interval as fetching. If GPS cannot supply a backend, it stops, clears validity, disables gpsActive and sends a notification; the non-GPS timer starts/fetches immediately and repeats (`:130`, `:160`). City/units changes also request data. Config enableGPS initializes a mutable `gpsActive`; runtime assignments can break that original binding.

Current implementation initializes location with `lon` but stores/uses `long` in the GPS path (`:26`, `:87`, `:138`); verify that path before modifying it. No network error/backoff model exists: empty output returns, invalid JSON logs, previous data remains. USCS visibility/pressure labels are hard-coded “m”/“psi” even though source field names are visibilityMiles/pressureInches; document actual behavior rather than assuming conversion accuracy.

## Startup helpers and update checks

`FirstRunExperience.load()` reloads `Directories.state/user/first_run.txt`. Only FileNotFound creates the marker, applies the bundled default wallpaper and launches `qs -p welcome.qml` (`S/FirstRunExperience.qml:17`, `:33`). The marker is written before the detached welcome/theme actions complete. `enableNextTime()` removes it; `disableNextTime()` writes it. The welcome notification summary/body properties are unused by this service's current first-run handler.

`ConflictKiller.load()` only forces instantiation. A Config ready-change handler starts pidof checks for kded6 and mako/dunst (`S/ConflictKiller.qml:18`). Each conflict is either killed automatically according to its option or triggers `qs -p killDialog.qml`. It checks these names, not all possible daemons, and does not continuously monitor/retry. The handler has no explicit already-ready initialization fallback; startup ordering matters.

`Updates.load()` similarly forces initialization. When Config is ready and enableCheck is true, `which checkupdates` determines availability, then refresh runs `checkupdates | wc -l`; a timer repeats every checkInterval minutes (`S/Updates.qml:29`). Advice flags use **strictly greater than** their thresholds. This service supports Arch's checkupdates only; do not infer distro-generic updates from SystemInfo. The pipeline does not expose checkupdates failures as a separate error state. The waffle button consumes the count; ii has no direct Updates consumer in the module search.

## Recipes and gotchas

### Add a singleton and use it in a panel

1. Add `Q/services/Example.qml` using the pattern below. Keep backend state/actions here and visual state in the panel. No checked-in qmldir export needs changing.
2. Add config defaults only if needed through the existing Config schema; choose Persistent for session/UI state and Directories for generated/cache paths. Follow [config and common](config-and-common.md).
3. Consume from a loaded panel with `import qs.services`, a binding such as `text: Example.status`, and an action such as `onClicked: Example.refresh()`. Do not instantiate `Example {}` for a singleton.
4. If its side effects must exist before a panel is loaded, expose a purposeful `load/refresh` and add the startup reference to the relevant entrypoint. A singleton referenced only from an optional panel is optional in practice.
5. If adding IPC/shortcuts, register them in the service that owns the action and give handlers typed signatures as existing services do. Test the actual panel family/entrypoint that consumes it.

```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string status: ""
    function refresh() { query.running = true }
    Process {
        id: query
        command: ["some-program", "--status"]
        stdout: StdioCollector {
            onStreamFinished: root.status = text.trim()
        }
    }
}
```

### Before changing an existing service

- Trace consumers and direct config reads with fish-compatible commands from the repository root:
  `rg -n 'Audio[.]' dots/.config/quickshell/ii/modules` and
  `rg -n 'Config.*options' dots/.config/quickshell/ii/services/Audio.qml`.
  Search dependent services too; some services (Emojis, KeyringStorage) reach panels indirectly.
- Reuse Process/collector objects for ongoing work; setting an already-running process's running property true is not a queue. Existing services sometimes explicitly stop/restart it. Concurrent AI chats also share a fixed temporary request/upload path.
- Prefer argument arrays. For Bash strings, use the existing shell-escaping helpers for untrusted text/paths. HyprlandConfig's interpolated strings and wallpaper thumbnail commands are not examples of fully general escaping.
- Preserve the distinction between file URLs and native paths: common Directories exposes both; `FileUtils.trimFileProtocol` is used before many command arguments.
- Services are per shell/entrypoint process, not system-wide daemons by themselves. Launching separate settings/welcome processes can instantiate their own singleton copies. Notification/Polkit ownership and startup ordering deserve runtime verification.
- Native dependencies differ: UPower, PipeWire, Bluetooth, MPRIS and Polkit use Quickshell service APIs; Network uses nmcli; updates are Arch-only; brightness/DDC needs usable devices; input synthesis depends on a working ydotool setup.
- `S/Privacy.qml:14` declares bool properties but assigns mapped arrays rather than an explicit nonempty test. No direct module `Privacy.*` use was found. Treat actual flag semantics as unverified; do not copy this as an activity-detection pattern.
- `S/Emojis.qml:23` has a sloppy-search branch referring to undeclared `sloppySearch,entries,scoreThreshold`; the normal fuzzy path uses its own prepared list. Verify/fix before exposing alternate search modes.
- `S/Brightness.qml:120` tests `monitor.animationEnabled`, whereas the declared property is `animateChanges`. Its DDC path also shares a setter Process across monitors. Verify animation/multi-monitor behavior before relying on it.
- LatexRenderer's cache key is expression-only, not font/color/theme, and render completion is emitted on process exit without checking success (`S/LatexRenderer.qml:33`). A previously “processed” hash does not prove a valid SVG.
- Runtime behavior was not exercised for this document: Quickshell/Hyprland, secrets, hardware, provider endpoints and network backends were not launched. Source paths and control flows above are verified by reading; external availability and successful execution remain unverified.
