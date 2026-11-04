# Settings application

## Purpose and scope

The settings UI is a standalone Quickshell application, `dots/.config/quickshell/ii/settings.qml`, with eight pages in `dots/.config/quickshell/ii/modules/settings/`. It edits the same persisted options as the desktop shell. There is no settings-specific configuration store and no Apply/Save transaction in this UI.

Paths below are repo-relative. `Q` abbreviates `dots/.config/quickshell/ii`; abbreviated source citations expand with that prefix. See [config and common](config-and-common.md) for the full schema/persistence/widget layer, [services](services.md) for backend side effects, and [architecture](architecture.md) for process and module structure.

## Launching and window lifecycle

- Installed config: `qs -p ~/.config/quickshell/ii/settings.qml`. For the repository checkout, from the repository root: `qs -p dots/.config/quickshell/ii/settings.qml`. These commands work in fish. Use the relevant checkout path if working in a worktree.
- The current default Hyprland binding is **Super+I** (`dots/.config/hypr/hyprland/keybinds.lua:354`). It executes `settingsApp`, defined in `dots/.config/hypr/hyprland/variables.lua:16`: `launch_first_available.sh` first tries `qs -p ~/.config/quickshell/$qsConfig/settings.qml`, then system settings alternatives. `qsConfig` defaults to `ii` (`:5`).
- Waffle's Start context menu and action-center footer launch `["qs", "-p", Quickshell.shellPath("settings.qml")]` (`Q/modules/waffle/bar/StartButton.qml:51`, `Q/modules/waffle/actionCenter/mainPage/MainPageFooter.qml:46`). This is a separate app process, not a panel toggled through `GlobalStates`.
- Entry pragmas request QApplication, Basic Qt Quick Controls style, suppress reload popups, set flickable deceleration, and set `QT_SCALE_FACTOR=1` (`Q/settings.qml:1`).
- The `ApplicationWindow` is immediately visible; closing calls `Qt.quit()` (`Q/settings.qml:74`). Default size is 1100×750, minimum 750×500 (`:87`). Titlebar visibility/alignment use `windows.showTitlebar` and `windows.centerTitle` (`:125`).
- On completion it calls `MaterialThemeLoader.reapplyTheme()` and sets this process's `Config.readWriteDelay = 0` (`:78`). The desktop shell has its own singleton instance; file watching synchronizes options between processes.

## Key files and page map

`Q/settings.qml:25` is the explicit navigation registry. It stores translated name, Material icon, optional icon rotation, and a relative component URL. Page order is the array order.

| Page file below `Q/modules/settings/` | Sections / primary config areas |
| --- | --- |
| `QuickConfig.qml` | Wallpaper preview, random/local wallpaper actions, light/dark preference, palette type, transparency, ii bar position/style and screen rounding; `background.wallpaperPath`, `appearance.*`, `bar.*` (`:59`, `:229`) |
| `GeneralConfig.qml` | Audio protection, battery thresholds/suspend, UI language and translation generation, AI/weeb policies, sounds, time formats, work safety; `audio`, `battery`, `language`, `policies`, `sounds`, `time`, `workSafety` (`:19`, `:132`, `:194`, `:265`, `:289`, `:338`) |
| `BarConfig.qml` | Notification indicator, position/hiding/corners/groups, tray pin inversion, utility buttons, weather visibility, workspace numbering, tooltips; `bar.*`, `tray.invertPinnedItems` (`:10`, `:23`, `:144`, `:167`, `:254`, `:338`) |
| `BackgroundConfig.qml` | Parallax, clock enable/placement/styles and digital/cookie details, quote, weather widget; `background.parallax.*`, `background.widgets.*` (`:10`, `:55`, `:572`) |
| `InterfaceConfig.qml` | Cheatsheet, dock, lock/security/style, notifications, overlays/crosshair/image, region selector/Lens, sidebars and quick-toggle layout/sliders/corners, OSD timeout, overview layout, wallpaper picker, fonts (`:10`, `:102`, `:144`, `:253`, `:371`, `:465`, `:694`, `:711`, `:808`, `:822`) |
| `ServicesConfig.qml` | AI system prompt, music-recognition timeouts, networking user agent, resource polling, capture save paths, search algorithm/prefixes/engine, weather location/units/polling (`:10`, `:27`, `:55`, `:70`, `:88`, `:113`, `:232`) |
| `AdvancedConfig.qml` | Wallpaper color-generation targets: shell/utilities, Qt, terminal; terminal force-dark/harmony/threshold/foreground boost, all under `appearance.wallpaperTheming.*` (`:9`) |
| `About.qml` | Distro logo/name/links from `SystemInfo`; dotfiles links. Uses the same page layout, not config controls (`:12`, `:81`) |

The names describe page organization, not an automatic schema browser. Adding a key to `Config.qml` does not add a control or page.

## Navigation and layout

`Q/settings.qml:72` owns integer `currentPage`. The navigation rail has one `NavigationRailButton` per page (`:212`), and expands by default above 900px width (`:173`). The config-file action opens `${Directories.config}/illogical-impulse/config.json`; its alternate/right-click action copies the path and displays brief feedback (`:179`).

Keyboard handling in `Q/settings.qml:102` provides:

- Ctrl+PageDown/PageUp: next/previous, clamped at the ends.
- Ctrl+Tab/Ctrl+Backtab: cycle forward/backward with wraparound.

`pageLoader` is gated by `Config.ready` (`Q/settings.qml:241`). Its initial source is the first page. Page changes fade the current content out, change `source` to the selected URL, add a 20px top offset, then fade/move the new page in (`:249`). Only one page component is loaded here; transient page-local state is recreated on navigation. Put durable options in `Config`, not page-local properties.

All eight pages use `ContentPage` and `forceWidth: true`. The reusable layout components actually live in **`Q/modules/common/widgets/`**, not `modules/settings/`:

| Component | Contract |
| --- | --- |
| `ContentPage.qml:6` | `StyledFlickable`; default content aliases a centered `ColumnLayout`. `baseWidth` defaults to 600, `forceWidth` chooses that fixed width, bottom padding defaults to 100. |
| `ContentSection.qml:7` | Full-width column with `title`, optional Material `icon`, and nested default content. |
| `ContentSubsection.qml:6` | Smaller heading, optional `tooltip` info affordance, nested default content. |
| `ConfigRow.qml:4` | `RowLayout`, spacing 4; `uniform` maps to `uniformCellSizes`. |

Use `Layout.*` properties in these layouts; match neighboring pages' width/spacing conventions. Labels/tooltips use `Translation.tr(...)`; Material icon names go through the common widgets. The settings app uses `Appearance`/Material styling regardless of the selected panel family.

## Reusable controls and binding convention

The `Config*` prefix is visual/conventional. These widgets **do not take a config key or persist values themselves**. The page binds a current value and writes it back in a handler.

| Shared widget (`Q/modules/common/widgets/`) | Inputs and write-back pattern | Existing example |
| --- | --- | --- |
| `ConfigSwitch.qml:7` | Inherits `RippleButton`; `text`, `buttonIcon`, `checked`; click toggles `checked`. Page uses `checked: Config.options.…` plus `onCheckedChanged`. Inner `StyledSwitch` forwards clicks to the root. | `modules/settings/GeneralConfig.qml:23` |
| `ConfigSpinBox.qml:6` | `text`, **`icon`**, aliases `value`, `from`, `to`, `stepSize` to `StyledSpinBox`. Page uses `value: …` plus `onValueChanged`. | `GeneralConfig.qml:36` |
| `ConfigSlider.qml:7` | `text`, **`buttonIcon`**, value alias, `from`, `to`, `stopIndicatorValues`, `usePercentTooltip`, `textWidth`; wraps `StyledSlider`. Page writes `onValueChanged`. | `BackgroundConfig.qml:231` |
| `ConfigSelectionArray.qml:8` | Flow of `SelectionGroupButton`s. `options` is a list of `{displayName, icon?, value}`; `currentValue` determines highlight; emits `selected(newValue)`. Page must handle `onSelected`; the widget does not assign `currentValue`. | `QuickConfig.qml:173` |
| `MaterialTextArea.qml` | Used directly with `text`, `placeholderText`, wrap mode, and `onTextChanged`. Some callers use `Qt.callLater` for writes. | `ServicesConfig.qml:14` |
| `StyledComboBox.qml` | Used directly with model/textRole, a config-derived `currentIndex`, and `onActivated` converting index back to the stored value. | `GeneralConfig.qml:140` |

Booleans/numbers follow this concrete pattern (`GeneralConfig.qml:23`, `:36`):

```qml
ConfigSwitch {
    text: Translation.tr("Earbang protection")
    checked: Config.options.audio.protection.enable
    onCheckedChanged: Config.options.audio.protection.enable = checked
}
```

Conversions belong in both directions: `BackgroundConfig.qml:42` displays `background.parallax.workspaceZoom * 100` and writes `value / 100`; `AdvancedConfig.qml:58` does the same for terminal harmony. Selection values can be strings, booleans, numbers, or an encoding: `BarConfig.qml:33` packs bottom/vertical into two bits and unpacks the selected value into two config properties.

Dependent controls use `enabled:` bindings. For example, the max-volume row follows `audio.protection.enable` (`GeneralConfig.qml:34`), and cookie clock hour marks depend on dial style (`BackgroundConfig.qml:336`). A tooltip should explain why a control is unavailable or what a nonobvious unit means.

## Persistence and side effects

`Q/modules/common/Config.qml:10` exposes `options` as the alias of `configOptionsJsonAdapter`. The persisted definitions are **inside the `JsonAdapter` in its `FileView`** (`:64`, `:78`), not arbitrary properties on the outer singleton.

- A nested group is a typed `property JsonObject …: JsonObject { … }`; leaves have defaults and QML types. This is the source of option names/types/defaults.
- `onAdapterUpdated` restarts the file-write timer, which calls `writeAdapter()`; `watchChanges`/`onFileChanged` reload external edits (`:46`, `:55`, `:64`). The settings app sets the delay to zero, so controls write without an explicit save action.
- `Config.ready` becomes true after file load (`:71`). Keep page loading gated to avoid controls writing defaults before persistent options load.
- Side effects are not uniformly implemented by controls. Many consumers react to config changes; some page actions also launch scripts. For example, palette-type selection writes `appearance.palette.type` **and** invokes `Directories.wallpaperSwitchScriptPath --noswitch` (`QuickConfig.qml:173`); light/dark buttons invoke the switch script with mode flags (`:26`).
- Random-wallpaper actions use a `Process` and status parser (`QuickConfig.qml:14`); translation generation uses `Directories.aiTranslationScriptPath` and a locale (`GeneralConfig.qml:13`, `:184`). Copy the appropriate existing behavior rather than assuming every setting needs a subprocess.

## Recipe: expose a new config option

1. **Choose the actual consumer and group.** Search its reads and related defaults first. A waffle-only bar option belongs under `waffles.bar`, not the ii `bar` group. Read [panels waffle](panels-waffle.md) / [panels ii](panels-ii.md) before reusing a similarly named key.
2. **Define the typed default in `Q/modules/common/Config.qml`.** Add the leaf inside the existing `JsonAdapter` group. For a new group, use `property JsonObject groupName: JsonObject { … }` inside that adapter. Do not put it on the outer `Singleton`, and do not rely only on a user's JSON file. Example *new, hypothetical* leaf: inside `waffles.bar` (`:620`), add `property bool exampleEnabled: true`; the runtime path is then `Config.options.waffles.bar.exampleEnabled`.
3. **Wire the consumer.** Read that exact property in the relevant panel/service. Merely exposing a switch stores a value; it does not implement behavior. Set the default so an existing user without the new JSON key gets the intended behavior.
4. **Pick a page and control.** Put related fields in an existing `ContentSection`/`ContentSubsection`. Reuse a switch for a boolean, spinbox/slider for bounded numeric input, selection array for a small explicit set, text area for text, combo box for a longer model. Existing pages already import `qs.modules.common`, `qs.modules.common.widgets`, and `qs.services` for `Translation`.
5. **Bind read and write explicitly.** For the hypothetical boolean, use `checked: Config.options.waffles.bar.exampleEnabled` and `onCheckedChanged: Config.options.waffles.bar.exampleEnabled = checked`. For selections use `currentValue`/`onSelected`; for a number define `from`, `to`, `stepSize`, displayed units, and inverse conversion. Keep the option type and stored enum values consistent with the consumer.
6. **Add labels and constraints.** Wrap visible strings in `Translation.tr`, use the correct icon property (`buttonIcon` for switches/sliders; `icon` for spinboxes), and add `enabled`/tooltips for prerequisites. Decide whether a shared config reaction or explicit action should perform any expensive side effect.
7. **Register a page only if needed.** Create a `ContentPage` component under `Q/modules/settings/`, then add `{name, icon, component: "modules/settings/NewConfig.qml"}` to `Q/settings.qml:25`. No additional navigation implementation is needed; the rail and shortcuts use the registry. Existing-page additions need no registry edit.
8. **Verify in a running desktop when available.** Open the app from the intended checkout, confirm initial value, change it, inspect the persisted JSON, navigate away/back and reopen the app, verify the shell consumer updates, and try editing the JSON externally while the page is open. For numeric/enum controls verify bounds and both conversion directions. Check dependent controls and both panel families when the key is shared. Do not launch a desktop compositor just to perform documentation work.

## Welcome reuse

`Q/welcome.qml` is a separate application, not another page in the settings registry. It imports the same common widget layer (`:15`), reapplies the theme and sets `Config.readWriteDelay = 0` (`:33`), and lays out a `ContentPage` with sections and `ConfigSelectionArray`s bound directly to `Config.options` (`:138`, `:149`). It does **not** import/load `modules/settings/QuickConfig.qml` or the other settings page files. Update common control behavior when both apps should change; edit both applications explicitly when adding the same option to both flows. Its closing notification points users to Super+I for Settings (`:28`).

## Gotchas and verification limits

- This UI deliberately exposes a subset: `QuickConfig.qml:327` tells users to inspect the config file for remaining options. There is no automatic property-to-control generation.
- Family selection and `waffles.*` have no controls in the current `modules/settings/` pages. Quick/Bar position controls write `bar.bottom`/`bar.vertical`, while waffle reads `waffles.bar.bottom`. Background widgets/parallax and several interface styling controls similarly target ii behavior. Avoid promising universal effects from page labels.
- Properties are changed live. There is no rollback/cancel draft model. Some handlers write on **value change**, including changes caused by binding/initialization, rather than only explicit user actions. Retain the `Config.ready` loading gate and check synchronization if adding coercion or dependencies.
- `InterfaceConfig.qml:269` uses `notifications.forceMonitor.enable/name`, but the schema declares `notifications.monitor.enable/name` (`Q/modules/common/Config.qml:402`). This is a source mismatch; this control's runtime behavior is **unverified**, and it should not be copied as a schema pattern.
- Text edits can persist partial input. `ServicesConfig.qml:19` defers the AI prompt write with `Qt.callLater`, while its city field writes directly (`:262`). Follow neighboring semantics deliberately instead of assuming a form submission exists.
- The entry defines `firstRunFilePath`, `firstRunFileContent`, and `showNextTime` (`Q/settings.qml:21`), but the settings entry does not use them in its body. First-run behavior should be traced through `welcome.qml`/`FirstRunExperience`, not inferred from these declarations.
- This documentation was verified statically against source. App launch, file synchronization, rendering, keyboard focus, and backend side effects were not exercised in a running Quickshell session.
