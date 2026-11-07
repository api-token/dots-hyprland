import QtQuick

// One T3 Code thread, as sent by scripts/t3/t3-sidebar-bridge.mjs. Kept stable per id so
// delegates survive updates.
QtObject {
    required property var data

    // Timestamps are often null. Skip parsing those: Date.parse("") takes ~1 ms in QML's JS
    // engine, which froze the shell for seconds on a snapshot.
    function ms(iso) {
        return iso ? Date.parse(iso) || 0 : 0;
    }

    readonly property string threadId: data.id
    // "local", or the remote's URL from sidebar.t3.remotes
    readonly property string machine: data.machine ?? "local"
    readonly property string projectId: data.projectId ?? ""
    readonly property string title: data.title ?? ""
    // approval | input | request | waiting | working | limited | failed | ready
    readonly property string status: data.status ?? "ready"
    // pinned | active | snoozed | settled
    readonly property string section: data.section ?? "active"
    readonly property string branch: data.branch ?? ""
    readonly property real updatedAt: ms(data.updatedAt)
    readonly property string orderKey: (section === "pinned" ? data.pinOrderKey : data.activeOrderKey) ?? ""
    // Running, so it goes on the Working shelf (T3's isThreadWorking: not waiting on the user).
    readonly property bool isWorking: status === "working" || status === "waiting"
    readonly property bool needsAttention: ["approval", "input", "request"].includes(status)
    readonly property bool unseen: {
        const done = ms(data.latestRunCompletedAt);
        const seen = ms(data.lastVisitedAt);
        return status === "ready" && done > 0 && seen > 0 && done > seen;
    }
}
