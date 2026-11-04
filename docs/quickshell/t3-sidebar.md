# Plan: T3 Code sidebar replaces the left sidebar

Status: **phases 1–3 done**: the bridge and the navigator work against the live server, and the old
tabs are deleted. Branch `t3-integration`. Paths are relative to
`dots/.config/quickshell/ii/` unless they start with `t3code/` (the T3 Code clone at
`~/git/t3code`, read at commit `567a105705`). Line numbers drift; re-read before editing.

## Decisions (from the user)

- The ii left sidebar becomes a T3 Code **navigator only**: projects/threads with live status.
  Clicking hands off to the T3 desktop window. No chat, composer or approvals in the shell.
- The AI chat, Translator and Anime tabs are **removed**.
- When T3 isn't reachable, the panel shows an **offline state with a launch button**.
- MicroTeX is dropped from the installer too (its only user was the AI chat's LaTeX rendering).

## Out of scope

Waffle family (it maps `sidebarLeftOpen` to its own action center,
`modules/waffle/actionCenter/WaffleActionCenter.qml`), write actions (pin/archive/rename/snooze),
search, drag-reorder, guest sharing, and an embedded web view. Multiple machines were added later;
see [Other machines](#other-machines).

## How T3 exposes the data

- **Server:** the desktop app runs a local server. Host/port/pid are in
  `~/.t3/userdata/server-runtime.json` (currently `127.0.0.1:3773`).
- **Transport:** Effect RPC over one WebSocket, `GET /ws?orchestrationProtocol=2`. A missing or old
  protocol gets HTTP 426 (`t3code/apps/server/src/ws.ts:3440`). Frames are JSON:
  `{"_tag":"Request","id","tag","payload","headers":[]}` → `Chunk`… → `Exit`. The client must send
  `{"_tag":"Ack","requestId"}` after each `Chunk` or the stream stalls, and must answer `Ping`
  (`t3code/.repos/effect/packages/effect/src/rpc/RpcServer.ts`). The *client* sends `Ping` and the
  server answers `Pong`; the bridge uses that as its liveness check.
- **Live feed:** `orchestration.subscribeShell` (`t3code/packages/contracts/src/orchestrationV2.ts`)
  sends a `snapshot` (projects, threads), then `project.updated/removed` and
  `thread.updated/removed` events with a `sequence`. This is the same feed the web sidebar uses.
  - A snapshot that has `resolvedRepositoryIdentityRoots` and no threads is a project-metadata
    refresh (`t3code/apps/server/src/ws.ts`, `loadProjectMetadataSnapshot`). It must not clear the
    thread list. One arrives right after the first snapshot.
  - Threads include subagent children (562 of 1019 live). The web sidebar hides
    `lineage.relationshipToParent == "subagent"` and `lineage.sideChat` (`isListedThreadLineage`).
  - Projects use `title` and `workspaceRoot`, not `name`/`root`.
  - The live snapshot is ~2.6 MB; filtered bridge output is ~180 KB.
- **Auth:** needs scope `orchestration:read`. Issue a token once, by hand:
  `~/.t3/bin/t3 auth session issue --scope orchestration:read --label ii-sidebar --token-only >
  ~/.config/illogical-impulse/t3-token` (run with `umask 077`; it writes a session row to the live
  T3 DB). The flag is `--scope`, not `--scopes`. The desktop app installs the `t3` shim at
  `~/.t3/bin/t3`, which is not on `PATH`. Exchange it for a socket ticket via `POST /api/auth/websocket-ticket`, then connect
  with `?wsTicket=…`. Requests without an `Origin` header are allowed.
- **Handoff:**
  - Open a thread: `xdg-open t3code://threads/<environmentId>/<threadId>`. The `environmentId` is
    from `GET /.well-known/t3/environment`.
    Verified: it reaches the running instance (no second window). `misc.focus_on_activate` is
    already `true` in the defaults (`dots/.config/hypr/hyprland/general.lua:287`), so focus should
    follow; not yet seen from another workspace.
  - New thread in a project: `~/.t3/bin/t3 app <projectRoot>`, which goes over the desktop control
    socket. Not run in the spike, to avoid hijacking the open window.
  - Launch when offline: `gtk-launch com.t3tools.T3Code`.
- **Web sidebar default:** a flat list in sections (Pinned / Active / Working / Snoozed / Settled,
  `t3code/apps/web/src/components/Sidebar.logic.ts`). Grouping by project is an opt-in mode.
- **Stability risk:** this is an internal API with daily churn (357 commits to
  `packages/contracts` in 30 days). It is versioned for old clients, though: new fields are optional
  and there is a protocol gate. The client must decode tolerantly and read only the fields below.

## Design

```
T3 server ──ws──▶ scripts/t3/t3-sidebar-bridge.mjs ──NDJSON stdout──▶ services/T3.qml ──▶ sidebar UI
                  (spawned by Process, restarted on exit)
```

**Bridge (Node ≥ 22, built-in `WebSocket`, no npm deps, ~200 lines).** It keeps the RPC framing out
of QML and can be run by hand for debugging.
- Reads the port from `server-runtime.json` and the token from a 0600 file.
- Gets a ticket, subscribes to the shell feed, and handles Ack/Ping.
- Reconnects with backoff.
- Prints one JSON line per change. The line types are listed at the top of the script:
  `state`, `snapshot`, `projects`, `project`, `thread`, `removed`.
- Fields it reads: thread `id, projectId, title, lineage, deletedAt, status, activityRunStatus,
  blockedOnThreadWait, pendingRuntimeRequest, pendingGuestMessageCount, lastErrorClass, pinnedAt,
  settledAt, snoozedUntil, lastVisitedAt, latestRunCompletedAt, updatedAt, branch, pinOrderKey,
  activeOrderKey`; project `id, title, workspaceRoot`.
- It derives each thread's `status` (approval / input / request / waiting / working / limited /
  failed / ready, after `resolveSidebarThreadStatus` in `Sidebar.logic.ts`) and `section`
  (snoozed / settled / pinned / active), so QML does no protocol logic.
- `state.error` is one of `no-token`, `unauthorized`, `offline`, `protocol`, or `ticket <status>`.

**`services/T3.qml` (singleton).**
- Runs the bridge with `Process` + `SplitParser`, following the pattern in `services/Network.qml`.
- Keeps stable per-thread objects keyed by id, like Network's `WifiAccessPoint` handling.
- Exposes `online`, `error`, sorted `threads`, `attentionCount` (threads that need approval or
  input), `openThread(id)`, `newThread(projectId)` and `launch()`.

**UI.** Rewrite `modules/ii/sidebarLeft/SidebarLeftContent.qml`, keeping its filename and
`scopeRoot` property so `SidebarLeft.qml` (window, focus grab, extend, pin, detach) stays untouched.
- Content:
  - Header with a "new thread" button.
  - Sectioned thread list, matching T3's sidebar with its Working shelf on: Pinned / Waiting / Working
    / Snoozed, then Settled collapsed (first 30). Waiting and Working split the unpinned active
    threads (T3's unlabeled main list and its Working shelf); a thread is Working when its status
    is `working` or `waiting` (running but blocked on another thread), after `isThreadWorking` in
    `t3code/packages/client-runtime/src/state/threadInbox.ts`. Threads needing approval or input
    stay in Waiting.
  - "New thread" opens an inline project picker (most recently active first).
  - Rows show the title, project name, a status icon, and the relative time.
  - Offline or setup state: either "T3 isn't running, Launch", or "No token, run `<cmd>`".
- Clicking a row opens the thread and closes the panel.
- Notification and Wi-Fi lists are references for the list, delegate and empty-state patterns
  (`modules/common/widgets/NotificationListView.qml`, `modules/ii/sidebarRight/wifiNetworks/`).

**Config.** `Config.options.sidebar.t3.tokenFile`; empty (the default) means
`~/.config/illogical-impulse/t3-token`. The endpoint is read from `server-runtime.json`.

## Other machines

The local server's shell feed has only its own threads, even when the T3 app is connected to other
machines (T3 merges those in the client). So the bridge connects to each machine itself.

- **Config.** `sidebar.t3.remotes` in `~/.config/illogical-impulse/config.json`, a list of
  `{ "url": "http://ryan-arch:3773", "tokenFile": "" }`. An empty `tokenFile` means
  `~/.config/illogical-impulse/t3-token-<host>`. The URL must reach that machine's T3 server
  directly, such as over Tailscale; its server must listen beyond loopback (for example `t3 up --lan`; the
  `host` in its `server-runtime.json` shows what it listens on). T3 Connect's relay is not supported.
- **Token.** Issued on the remote, saved here:
  `umask 077; ssh <host> '~/.t3/bin/t3 auth session issue --scope orchestration:read --label ii-sidebar-<this-machine> --token-only' > ~/.config/illogical-impulse/t3-token-<host>`.
  The panel's notice row copies this command. Revoke it in that machine's Settings → Sharing &
  access.
- **Bridge.** `--remotes '<json>'`; one reconnect loop per machine. Every output line has a
  `machine` key: `local`, or the remote's URL.
- **Service.** Threads are keyed by machine and id. A machine that goes offline has its threads
  dropped until it reconnects, so no stale status shows. `online`/`error` stay this machine's, so
  the offline screen only appears when the local T3 app is down. A change to `remotes` restarts the
  bridge: a running `Process` ignores command changes, and `Config` can load after it starts.
- **Clicks.** A remote thread opens with that machine's environment id
  (`t3code://threads/<environmentId>/<threadId>`), which needs the T3 app to be connected to that
  machine too. "New thread" lists only this machine's projects, since `t3 app <root>` opens a local
  path.

**QML notes.** `T3.*Threads` are `var` arrays, not `list<T3Thread>`: `ScriptModel.values` rejects a
`QQmlListReference`. Sorting re-runs on a debounced `revision` counter. The bridge process starts with
the bar (the bar button reads `T3.attentionCount`).

**Testing without reloading the live shell.** Make a temp dir that symlinks every entry of
`dots/.config/quickshell/ii/` except `shell.qml`, add a `shell.qml` with a `FloatingWindow` holding
`SidebarLeftContent { scopeRoot: QtObject { property bool pin: true; property bool detach: false } }`,
and run `qs -p <dir>/shell.qml`. It needs the `shapes` submodule initialized, and `Directories` wipes
the shell's cache dirs on start.

## Touch set

| Change | Files |
|---|---|
| New | `scripts/t3/t3-sidebar-bridge.mjs`, `services/T3.qml`, row delegate(s) in `modules/ii/sidebarLeft/` |
| Rewrite | `modules/ii/sidebarLeft/SidebarLeftContent.qml` |
| Edit | `modules/ii/bar/LeftSidebarButton.qml`: drop the `Ai`/`Booru` bindings, show T3 `attentionCount` |
| Edit | `modules/common/Config.qml`: add `sidebar.t3` |
| Remove | Remaining tab code: `AiChat.qml`, `Translator.qml`, `Anime.qml`, `aiChat/`, `translator/`, `anime/`, and the tab-only helpers in `sidebarLeft/` |
| Remove | Services and state: `services/Ai.qml`, `services/ai/`, `services/Booru*.qml`, `services/LatexRenderer.qml`, plus their `Persistent`/`Directories` entries, `Config.qml` keys and settings-page controls |
| Deps | Add `nodejs`. Drop `translate-shell` if nothing else uses it. Apply to all four distros, per [distros.md](../distros.md) |
| Docs | `panels-ii.md` (sidebarLeft section), `services.md`, `settings-app.md` |
| Unchanged | `SidebarLeft.qml`, `GlobalStates`, IPC/shortcuts, Hyprland binds and rules, family loaders, screen corners |

Keep `policies.weeb`: wallpaper features still use it. `policies.ai` loses its only consumer.

## Phases

1. **Spike (done).** `scripts/t3/t3-sidebar-bridge.mjs` ran against `0.1.7-nightly.20261104`:
   ticket flow, acks, ping/pong over 50 s, live updates, and the `no-token`, `unauthorized` and
   `offline` states all work. The nightly's schema matches the clone for the fields above.
2. **Navigator (done).** `services/T3.qml`, `services/t3/T3Thread.qml`, the new
   `SidebarLeftContent.qml` and `T3ThreadRow.qml`, and the bar button dot. Checked in the test
   harness with live data: thread list, settled expand, project picker, no-token and offline
   states. Clicks (`xdg-open`, `t3 app`) were not exercised from the panel.
3. **Removal (done).** Deleted the tabs and helpers, `Ai`/`services/ai/`, `Booru`,
   `BooruResponseData`, `LatexRenderer`, `defaults/ai/prompts/`, `scripts/ai/show-installed-ollama-models.sh`,
   their `Config`/`Persistent`/`Directories` entries, `policies.ai`, and the settings/welcome
   controls. Deps: `translate-shell` → `nodejs` in the widgets group on all four distros (Arch
   `pkgrel=8`, Gentoo `-r6`); MicroTeX removed everywhere (Arch also lists it as deprecated). Kept:
   `scripts/ai/gemini-*.sh` (wallpaper categorizing, UI translation), `KeyringStorage`,
   `GoogleCloud`, `policies.weeb`. Users' `config.json`/`states.json` keep the old keys; nothing
   migrates them, and they are ignored.
4. **Docs (done with each phase).** `panels-ii.md`, `services.md`, `settings-app.md`,
   `config-and-common.md`, `architecture.md`, `distros.md`, `setup-and-install.md`.

## Open / unverified

- Opening a remote thread from the panel (the `t3code://` link with the remote's environment id)
  was not clicked through; the list itself was checked live against Ryan-Arch
  (`0.1.4-nightly.20261028`, protocol 2).
- Focus on `xdg-open` when T3 is on another workspace (expected, given `focus_on_activate`).
- `t3 app <path>` from the shell (help text matches; not run).
- The Gemini scripts read `apiKeys.gemini` from the keyring, which only the removed chat's `/key`
  command wrote. An existing key keeps working; a new one must be stored by hand.
- Package changes were checked by reading, not by running an install on each distro.
- Removing the AI code makes upstream (`end-4`) merges conflict in those files. That is accepted
  as a cost of the decision.
