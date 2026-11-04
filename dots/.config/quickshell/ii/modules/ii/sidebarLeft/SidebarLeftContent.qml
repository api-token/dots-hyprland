import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// T3 Code navigator: lists threads from services/T3.qml; clicks open them in the T3 window.
// See docs/quickshell/t3-sidebar.md.
Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent

    property bool pickingProject: false
    property bool showSettled: false
    readonly property int settledLimit: 30
    readonly property bool hasOpenThreads: T3.pinnedThreads.length + T3.activeThreads.length + T3.workingThreads.length + T3.snoozedThreads.length > 0

    // This machine's projects, most recently active first, for the "new thread" picker.
    // Remote projects are left out: `t3 app <root>` opens a local path.
    readonly property var recentProjects: {
        const latest = {};
        for (const t of T3.threads.filter(t => t.machine === "local"))
            latest[t.projectId] = Math.max(latest[t.projectId] ?? 0, t.updatedAt);
        return Object.values(T3.projects.local ?? {}).sort((a, b) => (latest[b.id] ?? 0) - (latest[a.id] ?? 0));
    }

    function afterHandoff() {
        root.pickingProject = false;
        if (!root.scopeRoot.pin && !root.scopeRoot.detach)
            GlobalStates.sidebarLeftOpen = false;
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) root.pickingProject = false;
        }
    }

    component SectionHeader: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.topMargin: 8
        Layout.bottomMargin: 2
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    component ThreadSection: ColumnLayout {
        id: section
        property string title
        property var threads: []
        property int limit: -1
        Layout.fillWidth: true
        visible: threads.length > 0
        spacing: 2
        SectionHeader {
            visible: section.title !== ""
            text: `${section.title} · ${section.threads.length}`
        }
        Repeater {
            model: ScriptModel {
                values: section.limit < 0 ? section.threads : section.threads.slice(0, section.limit)
            }
            delegate: T3ThreadRow {
                required property var modelData
                thread: modelData
                Layout.fillWidth: true
                onOpened: root.afterHandoff()
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.sidebarPadding
        }
        spacing: root.sidebarPadding

        RowLayout { // Header
            Layout.fillWidth: true
            Layout.leftMargin: 6
            spacing: 4

            StyledText {
                text: "T3 Code"
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.larger
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.leftMargin: 6
                visible: T3.attentionCount > 0
                text: Translation.tr("%1 need you").arg(T3.attentionCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colPrimary
            }
            Item {
                Layout.fillWidth: true
            }
            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 36
                text: "add"
                enabled: T3.online
                toggled: root.pickingProject
                onClicked: root.pickingProject = !root.pickingProject
                StyledToolTip {
                    text: Translation.tr("New thread")
                }
            }
            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 36
                text: "open_in_new"
                onClicked: {
                    T3.launch();
                    root.afterHandoff();
                }
                StyledToolTip {
                    text: Translation.tr("Open T3 Code")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            clip: true

            StyledFlickable {
                id: flickable
                anchors {
                    fill: parent
                    margins: 6
                }
                visible: T3.online
                contentHeight: content.implicitHeight

                ColumnLayout {
                    id: content
                    width: flickable.width
                    spacing: 2

                    // New thread: pick a project
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.pickingProject
                        spacing: 2
                        SectionHeader {
                            text: Translation.tr("New thread in…")
                        }
                        Repeater {
                            model: ScriptModel {
                                values: root.pickingProject ? root.recentProjects : []
                            }
                            delegate: RippleButton {
                                id: projectRow
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: projectRowLayout.implicitHeight + 16
                                buttonRadius: Appearance.rounding.small
                                onClicked: {
                                    T3.newThread(projectRow.modelData.id);
                                    root.afterHandoff();
                                }
                                contentItem: RowLayout {
                                    id: projectRowLayout
                                    anchors {
                                        fill: parent
                                        leftMargin: 12
                                        rightMargin: 12
                                    }
                                    spacing: 10
                                    MaterialSymbol {
                                        text: "folder"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colSubtext
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: projectRow.modelData.name
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: projectRow.modelData.root ?? ""
                                            textFormat: Text.PlainText
                                            elide: Text.ElideMiddle
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Threads
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !root.pickingProject
                        spacing: 2

                        // Remote machines that aren't connected; their threads are hidden meanwhile.
                        Repeater {
                            model: ScriptModel {
                                values: T3.remoteProblems
                            }
                            delegate: RowLayout {
                                id: notice
                                required property var modelData
                                readonly property bool needsToken: modelData.error === "no-token" || modelData.error === "unauthorized"
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 4
                                spacing: 8
                                MaterialSymbol {
                                    text: notice.needsToken ? "key" : "cloud_off"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: `${notice.modelData.label || notice.modelData.host}: ` + (({
                                                "starting": Translation.tr("connecting…"),
                                                "offline": Translation.tr("unreachable"),
                                                "no-token": Translation.tr("no token"),
                                                "unauthorized": Translation.tr("token rejected"),
                                                "protocol": Translation.tr("unsupported T3 version")
                                            })[notice.modelData.error] ?? notice.modelData.error)
                                }
                                IconToolbarButton {
                                    visible: notice.needsToken
                                    Layout.fillHeight: false
                                    implicitHeight: 28
                                    text: "content_copy"
                                    onClicked: Quickshell.clipboardText = notice.modelData.command
                                    StyledToolTip {
                                        text: Translation.tr("Copy the command that creates a token (runs ssh)")
                                    }
                                }
                            }
                        }

                        ThreadSection {
                            title: Translation.tr("Pinned")
                            threads: T3.pinnedThreads
                        }
                        ThreadSection {
                            title: Translation.tr("Waiting")
                            threads: T3.activeThreads
                        }
                        ThreadSection {
                            title: Translation.tr("Working")
                            threads: T3.workingThreads
                        }
                        ThreadSection {
                            title: Translation.tr("Snoozed")
                            threads: T3.snoozedThreads
                        }
                        StyledText {
                            visible: !root.hasOpenThreads
                            Layout.fillWidth: true
                            Layout.margins: 16
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("No active threads")
                            color: Appearance.colors.colSubtext
                        }

                        // Settled, collapsed by default
                        RippleButton {
                            id: settledToggle
                            visible: T3.settledThreads.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            onClicked: root.showSettled = !root.showSettled
                            contentItem: RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 12
                                    rightMargin: 12
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: `${Translation.tr("Settled")} · ${T3.settledThreads.length}`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                MaterialSymbol {
                                    text: root.showSettled ? "expand_less" : "expand_more"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                        ThreadSection {
                            visible: root.showSettled
                            threads: root.showSettled ? T3.settledThreads : []
                            limit: root.settledLimit
                        }
                    }
                }
            }

            // Offline / setup states
            ColumnLayout {
                id: offline
                visible: !T3.online
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 20
                }
                spacing: 8

                readonly property bool needsToken: T3.error === "no-token" || T3.error === "unauthorized"
                readonly property var info: ({
                        "starting": ["hourglass_top", Translation.tr("Connecting to T3 Code…"), ""],
                        "offline": ["cloud_off", Translation.tr("T3 Code isn't running"), ""],
                        "no-token": ["key", Translation.tr("Connect to T3 Code"), Translation.tr("Create a read-only token by running this in a terminal:")],
                        "unauthorized": ["key_off", Translation.tr("T3 Code rejected the token"), Translation.tr("Create a new one by running this in a terminal:")],
                        "protocol": ["sync_problem", Translation.tr("This T3 Code version isn't supported"), Translation.tr("The sidebar speaks orchestration protocol 2.")],
                        "bridge": ["error", Translation.tr("The T3 bridge stopped"), Translation.tr("It needs Node.js 22 or newer. Retrying…")]
                    })[T3.error] ?? ["error", Translation.tr("Can't reach T3 Code"), T3.error]

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    padding: 12
                    iconSize: 48
                    text: offline.info[0]
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: offline.info[1]
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.larger
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.m3colors.m3outline
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: offline.info[2]
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3outline
                }
                Rectangle {
                    visible: offline.needsToken
                    Layout.fillWidth: true
                    implicitHeight: tokenCommandText.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    StyledText {
                        id: tokenCommandText
                        anchors {
                            fill: parent
                            margins: 8
                        }
                        text: T3.tokenCommand
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font {
                            family: Appearance.font.family.monospace
                            pixelSize: Appearance.font.pixelSize.smaller
                        }
                        color: Appearance.colors.colOnLayer2
                    }
                }
                RippleButtonWithIcon {
                    visible: offline.needsToken || T3.error === "offline"
                    Layout.alignment: Qt.AlignHCenter
                    materialIcon: offline.needsToken ? "content_copy" : "rocket_launch"
                    mainText: offline.needsToken ? Translation.tr("Copy command") : Translation.tr("Launch T3 Code")
                    onClicked: {
                        if (offline.needsToken) Quickshell.clipboardText = T3.tokenCommand;
                        else T3.launch();
                    }
                }
            }
        }
    }
}
