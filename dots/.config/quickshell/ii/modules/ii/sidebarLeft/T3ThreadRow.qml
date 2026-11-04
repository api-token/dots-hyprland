import qs.services
import qs.services.t3
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    required property T3Thread thread
    signal opened

    implicitHeight: row.implicitHeight + 16
    horizontalPadding: 12
    buttonRadius: Appearance.rounding.small
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onClicked: {
        T3.openThread(root.thread.threadId);
        root.opened();
    }

    readonly property var statusInfo: ({
            "approval": ["front_hand", Appearance.colors.colPrimary, Translation.tr("Needs approval")],
            "input": ["help", Appearance.colors.colPrimary, Translation.tr("Needs input")],
            "request": ["mark_chat_unread", Appearance.colors.colPrimary, Translation.tr("Guest message")],
            "working": ["progress_activity", Appearance.colors.colOnLayer1, Translation.tr("Working")],
            "waiting": ["hourglass_top", Appearance.colors.colSubtext, Translation.tr("Waiting")],
            "limited": ["timer_off", Appearance.colors.colError, Translation.tr("Usage limit")],
            "failed": ["error", Appearance.colors.colError, Translation.tr("Failed")],
            "ready": root.thread.unseen ? ["check_circle", Appearance.colors.colPrimary, Translation.tr("Done")] : ["chat_bubble", Appearance.colors.colSubtext, ""]
        })[root.thread.status] ?? ["chat_bubble", Appearance.colors.colSubtext, ""]

    function relativeTime(ms) {
        if (!ms) return "";
        const mins = Math.floor((T3.now - ms) / 60000);
        if (mins < 1) return Translation.tr("now");
        if (mins < 60) return `${mins}m`;
        if (mins < 1440) return `${Math.floor(mins / 60)}h`;
        return `${Math.floor(mins / 1440)}d`;
    }

    contentItem: RowLayout {
        id: row
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10

        MaterialSymbol {
            id: statusIcon
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            text: root.statusInfo[0]
            color: root.statusInfo[1]
            fill: root.thread.needsAttention || root.thread.unseen ? 1 : 0
            iconSize: Appearance.font.pixelSize.larger
            RotationAnimator on rotation {
                running: root.thread.status === "working"
                from: 0
                to: 360
                duration: 1200
                loops: Animation.Infinite
                onRunningChanged: if (!running) statusIcon.rotation = 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.thread.title || Translation.tr("Untitled thread")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: [T3.projectName(root.thread.projectId), root.statusInfo[2]].filter(s => s).join(" · ")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignTop
            text: root.relativeTime(root.thread.updatedAt)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
