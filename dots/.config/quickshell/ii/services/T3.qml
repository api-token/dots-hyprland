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
 * T3 desktop app's local server. Read-only: clicks hand off to the T3 window.
 * See docs/quickshell/t3-sidebar.md.
 */
Singleton {
    id: root

    property bool online: false
    // "" when online; otherwise starting | no-token | unauthorized | offline | protocol | bridge | other text
    property string error: "starting"
    property string environmentId: ""
    property var projects: ({}) // id -> { id, name, root }
    readonly property list<T3Thread> threads: []

    readonly property string tokenFile: Config.options.sidebar.t3.tokenFile || `${Directories.shellConfig}/t3-token`
    readonly property string cliPath: `${Quickshell.env("HOME")}/.t3/bin/t3`
    readonly property string tokenCommand: `umask 077; ~/.t3/bin/t3 auth session issue --scope orchestration:read --label ii-sidebar --token-only > ${root.tokenFile}`

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

    function projectName(projectId) {
        return root.projects[projectId]?.name ?? "";
    }

    function openThread(threadId) {
        if (!root.environmentId) return;
        Quickshell.execDetached(["xdg-open", `t3code://threads/${root.environmentId}/${threadId}`]);
    }

    // Opens the project in the T3 window, where a new thread can be started.
    function newThread(projectId) {
        const path = root.projects[projectId]?.root;
        if (path) Quickshell.execDetached([root.cliPath, "app", path]);
    }

    function launch() {
        Quickshell.execDetached(["gtk-launch", "com.t3tools.T3Code"]);
    }

    function upsert(data) {
        const existing = root.threads.find(t => t.threadId === data.id);
        if (existing) existing.data = data;
        else root.threads.push(threadComp.createObject(root, { data }));
    }

    function remove(threadId) {
        const i = root.threads.findIndex(t => t.threadId === threadId);
        if (i >= 0) root.threads.splice(i, 1).forEach(t => t.destroy());
    }

    function handle(msg) {
        switch (msg.type) {
        case "state":
            root.online = msg.online;
            root.error = msg.online ? "" : (msg.error ?? "offline");
            if (msg.environmentId) root.environmentId = msg.environmentId;
            return;
        case "snapshot": {
            const ids = new Set(msg.threads.map(t => t.id));
            for (const t of root.threads.filter(t => !ids.has(t.threadId))) root.remove(t.threadId);
            for (const t of msg.threads) root.upsert(t);
            root.setProjects(msg.projects);
            break;
        }
        case "projects":
            root.setProjects(msg.projects);
            break;
        case "project":
            root.projects = Object.assign({}, root.projects, { [msg.project.id]: msg.project });
            break;
        case "thread":
            root.upsert(msg.thread);
            break;
        case "removed":
            if (msg.kind === "thread") root.remove(msg.id);
            else {
                const p = Object.assign({}, root.projects);
                delete p[msg.id];
                root.projects = p;
            }
            break;
        }
        revisionTimer.restart();
    }

    function setProjects(list) {
        const p = {};
        for (const project of list) p[project.id] = project;
        root.projects = p;
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

    Process {
        id: bridge
        running: true
        command: ["node", FileUtils.trimFileProtocol(`${Directories.scriptPath}/t3/t3-sidebar-bridge.mjs`), "--token-file", root.tokenFile]
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
