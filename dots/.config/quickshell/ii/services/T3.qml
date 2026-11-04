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
    readonly property list<T3Thread> threads: []

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

    // Bumped (debounced) on any change so the sorted lists below recompute.
    property int revision: 0
    // Ticks for relative times.
    property real now: Date.now()

    // Sections match T3's sidebar: unpinned active threads split into Waiting (on you) and Working.
    function sorted(section) {
        root.revision; // dependency
        const inSection = section === "working" ? t => t.section === "active" && t.isWorking
            : section === "active" ? t => t.section === "active" && !t.isWorking
            : t => t.section === section;
        return root.threads.filter(inSection).sort((a, b) => {
            if (a.orderKey && b.orderKey && a.orderKey !== b.orderKey)
                return a.orderKey < b.orderKey ? -1 : 1;
            return b.updatedAt - a.updatedAt;
        });
    }
    readonly property var pinnedThreads: sorted("pinned")
    readonly property var activeThreads: sorted("active") // shown as "Waiting"
    readonly property var workingThreads: sorted("working")
    readonly property var snoozedThreads: sorted("snoozed")
    readonly property var settledThreads: sorted("settled")
    readonly property int attentionCount: {
        root.revision;
        return root.threads.filter(t => t.needsAttention && t.section !== "settled").length;
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
        const existing = root.threads.find(t => t.machine === machine && t.threadId === data.id);
        if (existing) existing.data = data;
        else root.threads.push(threadComp.createObject(root, { data }));
    }

    function removeWhere(predicate) {
        for (let i = root.threads.length - 1; i >= 0; i--) {
            if (predicate(root.threads[i])) root.threads.splice(i, 1).forEach(t => t.destroy());
        }
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
        case "projects":
            // Metadata refreshes can arrive in several chunks, each covering some projects.
            root.setProjects(machine, Object.values(Object.assign({}, root.projects[machine], Object.fromEntries(msg.projects.map(p => [p.id, p])))));
            break;
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
        revisionTimer.restart();
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
        id: revisionTimer
        interval: 150
        onTriggered: root.revision++
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
