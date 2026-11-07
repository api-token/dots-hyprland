pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services.t3
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * T3 Code threads for the left sidebar. Runs scripts/t3/t3-sidebar-bridge.mjs, which talks to the
 * T3 desktop app's local server and to each machine in sidebar.t3.remotes. Read-only: clicks hand
 * off to the T3 window. See docs/quickshell/t3-sidebar.md.
 */
Singleton {
    id: root

    // online and error describe this machine; the panel needs it, since clicks open the local app.
    property bool online: false
    // "" when online; otherwise starting | no-token | unauthorized | offline | protocol | bridge | other text
    property string error: "starting"
    // Machine key ("local" or a remote's URL) -> { key, label, online, error, environmentId }
    property var machines: ({})
    property var projects: ({}) // machine -> { projectId -> { id, name, root } }
    // A plain array and index, mutated in place so no binding re-runs per thread. A snapshot holds
    // hundreds of threads, and bindings over them re-ran on every change, freezing the shell for
    // seconds. Read the lists that refresh() publishes instead.
    property var threads: []
    property var threadIndex: ({}) // "machine|threadId" -> T3Thread

    readonly property string tokenFile: Config.options.sidebar.t3.tokenFile || `${Directories.shellConfig}/t3-token`
    readonly property string cliPath: `${Quickshell.env("HOME")}/.t3/bin/t3`
    readonly property string tokenCommand: `umask 077; ~/.t3/bin/t3 auth session issue --scope orchestration:read --label ii-sidebar --token-only > ${root.tokenFile}`

    // sidebar.t3.remotes entries are { url, tokenFile? }; the token file defaults to t3-token-<host>.
    readonly property var remotes: (Config.options.sidebar.t3.remotes ?? []).filter(r => r?.url).map(r => ({
                url: r.url,
                host: root.hostOf(r.url),
                tokenFile: r.tokenFile || `${Directories.shellConfig}/t3-token-${root.hostOf(r.url)}`
            }))
    // Remotes that aren't connected, for the panel's notices.
    readonly property var remoteProblems: root.remotes.map(r => Object.assign({}, r, root.machines[r.url] ?? { label: r.host, error: "starting" }, {
                command: root.remoteTokenCommand(r)
            })).filter(m => !m.online)

    function hostOf(url) {
        return url.replace(/^[a-z]+:\/\//, "").replace(/[:\/].*$/, "");
    }

    // Issues the token on the remote over ssh and saves it here.
    function remoteTokenCommand(remote) {
        return `umask 077; ssh ${remote.host} '~/.t3/bin/t3 auth session issue --scope orchestration:read --label ii-sidebar-${root.machines.local?.label || "remote"} --token-only' > ${remote.tokenFile}`;
    }

    // Ticks for relative times.
    property real now: Date.now()

    // Published by refresh(), debounced after any change.
    property var pinnedThreads: []
    property var activeThreads: [] // shown as "Waiting"
    property var workingThreads: []
    property var snoozedThreads: []
    property var settledThreads: []
    property int attentionCount: 0
    // This machine's projects, most recently active first, for the "new thread" picker.
    property var recentProjects: []

    // Sections match T3's sidebar: unpinned active threads split into Waiting (on you) and Working.
    function refresh() {
        const by = { pinned: [], active: [], working: [], snoozed: [], settled: [] };
        const latest = {};
        let attention = 0;
        for (const t of root.threads) {
            by[t.section === "active" && t.isWorking ? "working" : t.section]?.push(t);
            if (t.needsAttention && t.section !== "settled") attention++;
            if (t.machine === "local") latest[t.projectId] = Math.max(latest[t.projectId] ?? 0, t.updatedAt);
        }
        const order = (a, b) => {
            if (a.orderKey && b.orderKey && a.orderKey !== b.orderKey)
                return a.orderKey < b.orderKey ? -1 : 1;
            return b.updatedAt - a.updatedAt;
        };
        root.pinnedThreads = by.pinned.sort(order);
        root.activeThreads = by.active.sort(order);
        root.workingThreads = by.working.sort(order);
        root.snoozedThreads = by.snoozed.sort(order);
        root.settledThreads = by.settled.sort(order);
        root.attentionCount = attention;
        root.recentProjects = Object.values(root.projects.local ?? {}).sort((a, b) => (latest[b.id] ?? 0) - (latest[a.id] ?? 0));
    }

    function projectName(machine, projectId) {
        return root.projects[machine]?.[projectId]?.name ?? "";
    }

    // "" for this machine, so local rows stay unlabeled.
    function machineLabel(machine) {
        return machine === "local" ? "" : (root.machines[machine]?.label ?? root.hostOf(machine));
    }

    function openThread(thread) {
        const environmentId = root.machines[thread.machine]?.environmentId;
        if (!environmentId) return;
        Quickshell.execDetached(["xdg-open", `t3code://threads/${environmentId}/${thread.threadId}`]);
    }

    // Opens a local project in the T3 window, where a new thread can be started.
    function newThread(projectId) {
        const path = root.projects.local?.[projectId]?.root;
        if (path) Quickshell.execDetached([root.cliPath, "app", path]);
    }

    function launch() {
        Quickshell.execDetached(["gtk-launch", "com.t3tools.T3Code"]);
    }

    function upsert(machine, data) {
        data = Object.assign({ machine }, data);
        const key = `${machine}|${data.id}`;
        const existing = root.threadIndex[key];
        if (existing) {
            existing.data = data;
        } else {
            const t = threadComp.createObject(root, { data });
            root.threadIndex[key] = t;
            root.threads.push(t);
        }
    }

    function removeWhere(predicate) {
        root.threads = root.threads.filter(t => {
            if (!predicate(t)) return true;
            delete root.threadIndex[`${t.machine}|${t.threadId}`];
            t.destroy();
            return false;
        });
    }

    function handle(msg) {
        const machine = msg.machine ?? "local";
        switch (msg.type) {
        case "state":
            root.machines = Object.assign({}, root.machines, {
                [machine]: { key: machine, label: msg.label ?? "", online: msg.online, error: msg.online ? "" : (msg.error ?? "offline"), environmentId: msg.environmentId ?? "" }
            });
            if (machine === "local") {
                root.online = msg.online;
                root.error = msg.online ? "" : (msg.error ?? "offline");
            }
            // An unreachable machine's threads would show stale status, so drop them until it is back.
            if (!msg.online) {
                root.removeWhere(t => t.machine === machine);
                root.setProjects(machine, []);
            }
            break;
        case "snapshot": {
            const ids = new Set(msg.threads.map(t => t.id));
            root.removeWhere(t => t.machine === machine && !ids.has(t.threadId));
            for (const t of msg.threads) root.upsert(machine, t);
            root.setProjects(machine, msg.projects);
            break;
        }
        case "projects": {
            // Metadata refreshes can arrive in several chunks, each covering some projects.
            // (No Object.fromEntries: QML's JS engine lacks it.)
            const merged = Object.assign({}, root.projects[machine]);
            for (const p of msg.projects) merged[p.id] = p;
            root.setProjects(machine, Object.values(merged));
            break;
        }
        case "project":
            root.setProjects(machine, Object.values(Object.assign({}, root.projects[machine], { [msg.project.id]: msg.project })));
            break;
        case "thread":
            root.upsert(machine, msg.thread);
            break;
        case "removed":
            if (msg.kind === "thread") root.removeWhere(t => t.machine === machine && t.threadId === msg.id);
            else root.setProjects(machine, Object.values(root.projects[machine] ?? {}).filter(p => p.id !== msg.id));
            break;
        }
        refreshTimer.restart();
    }

    function setProjects(machine, list) {
        const p = {};
        for (const project of list) p[project.id] = project;
        root.projects = Object.assign({}, root.projects, { [machine]: p });
    }

    Component {
        id: threadComp
        T3Thread {}
    }

    Timer {
        id: refreshTimer
        interval: 150
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // A running Process ignores command changes, and Config can load after the bridge starts.
    readonly property string remotesArg: JSON.stringify(root.remotes.map(r => ({ url: r.url, tokenFile: r.tokenFile })))
    property bool restartingBridge: false
    onRemotesArgChanged: {
        if (!bridge.running) return;
        root.restartingBridge = true;
        bridge.running = false;
    }

    Process {
        id: bridge
        running: true
        command: ["node", FileUtils.trimFileProtocol(`${Directories.scriptPath}/t3/t3-sidebar-bridge.mjs`), "--token-file", root.tokenFile, "--remotes", root.remotesArg]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.handle(JSON.parse(line));
                } catch (e) {
                    console.warn("[T3] bad bridge line:", e);
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn("[T3] bridge:", line)
        }
        onRunningChanged: {
            if (running) return;
            if (root.restartingBridge) {
                // Machines removed from the config must not linger.
                root.restartingBridge = false;
                root.removeWhere(() => true);
                root.machines = {};
                root.projects = {};
                refreshTimer.restart();
                Qt.callLater(() => bridge.running = true);
                return;
            }
            // Node missing or the bridge crashed; it handles reconnects itself.
            root.online = false;
            root.error = "bridge";
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 5000
        onTriggered: bridge.running = true
    }
}
