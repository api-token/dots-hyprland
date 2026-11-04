import QtQuick

// One T3 Code thread, as sent by scripts/t3/t3-sidebar-bridge.mjs. Kept stable per id so
// delegates survive updates.
QtObject {
    required property var data
    readonly property string threadId: data.id
    readonly property string projectId: data.projectId ?? ""
    readonly property string title: data.title ?? ""
    // approval | input | request | waiting | working | limited | failed | ready
    readonly property string status: data.status ?? "ready"
    // pinned | active | snoozed | settled
    readonly property string section: data.section ?? "active"
    readonly property string branch: data.branch ?? ""
    readonly property real updatedAt: Date.parse(data.updatedAt ?? "") || 0
    readonly property string orderKey: (section === "pinned" ? data.pinOrderKey : data.activeOrderKey) ?? ""
    // Running, so it goes on the Working shelf (T3's isThreadWorking: not waiting on the user).
    readonly property bool isWorking: status === "working" || status === "waiting"
    readonly property bool needsAttention: ["approval", "input", "request"].includes(status)
    readonly property bool unseen: {
        const done = Date.parse(data.latestRunCompletedAt ?? "");
        const seen = Date.parse(data.lastVisitedAt ?? "");
        return status === "ready" && done > 0 && seen > 0 && done > seen;
    }
}
