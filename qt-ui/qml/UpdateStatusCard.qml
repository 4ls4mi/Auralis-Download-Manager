pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "TransferData.js" as TransferData

Frame {
    id: card

    property string stage: "available"
    property string installedVersion
    property string targetVersion
    property double installerBytes: 0
    property string actionLabel
    property bool announceChanges: false
    readonly property var colors: MaterialTheme.palette
    readonly property string headline: {
        switch (stage) {
        case "checking": return qsTr("Checking for updates…")
        case "rechecking": return qsTr("Confirming Auralis %1…").arg(targetVersion)
        case "connecting": return qsTr("Connecting to download Auralis %1…").arg(targetVersion)
        case "downloading": return qsTr("Downloading Auralis %1…").arg(targetVersion)
        case "verifying": return qsTr("Verifying the Auralis %1 installer…").arg(targetVersion)
        case "installing": return qsTr("Starting the Auralis %1 installer…").arg(targetVersion)
        case "closing": return qsTr("Closing Auralis to install %1…").arg(targetVersion)
        case "latest": return qsTr("Auralis is up to date")
        case "error": return qsTr("Update check unavailable")
        default: return qsTr("Auralis %1 is available").arg(targetVersion)
        }
    }
    readonly property string summary: installerBytes > 0 && targetVersion
        ? qsTr("Installed %1 · %2 installer").arg(installedVersion).arg(TransferData.bytes(installerBytes))
        : qsTr("Installed version %1").arg(installedVersion)
    readonly property string symbol: stage === "latest" ? "complete" : stage === "error" ? "details"
        : stage === "checking" || stage === "rechecking" ? "refresh" : "downloads"
    readonly property color accent: MaterialTheme.actionColor(stage === "error" ? "pause"
        : stage === "checking" || stage === "rechecking" || stage === "verifying" ? "clock" : "add", colors.light)
    readonly property color ground: MaterialTheme.mix(colors.background, colors.light ? "#ffffff" : "#050817", .22, 1)
    readonly property color face: MaterialTheme.mix(ground, accent, colors.light ? .13 : .20, 1)
    readonly property color ink: MaterialTheme.contrastInk(face)
    readonly property string attentionKey: stage + ":" + targetVersion
    property string lastAttentionKey
    property real sweepPosition: -.25

    signal actionRequested()

    padding: 9
    leftPadding: 13
    Accessible.role: Accessible.Grouping
    Accessible.name: headline
    Accessible.description: summary

    function drawAttention() {
        if (!visible || !stage || attentionKey === lastAttentionKey) return
        lastAttentionKey = attentionKey
        if (announceChanges && stage === "available")
            Accessible.announce(headline + ". " + summary)
        if (!MaterialTheme.reducedMotion) accentSweep.restart()
    }

    onAttentionKeyChanged: Qt.callLater(drawAttention)
    onVisibleChanged: {
        if (visible) Qt.callLater(drawAttention)
        else accentSweep.stop()
    }
    Component.onCompleted: Qt.callLater(drawAttention)

    NumberAnimation {
        id: accentSweep
        target: card
        property: "sweepPosition"
        from: -.25
        to: 1.05
        duration: 950
        easing.type: Easing.OutCubic
    }

    background: Rectangle {
        radius: 9
        color: card.face
        border.width: 1
        border.color: MaterialTheme.mix(card.colors.edge, card.accent, .76, 1)

        Item {
            anchors.fill: parent
            anchors.margins: 2
            clip: true
            Rectangle {
                visible: accentSweep.running && !MaterialTheme.reducedMotion
                x: parent.width * card.sweepPosition
                width: Math.max(32, parent.width * .22)
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: .50; color: MaterialTheme.rgba(card.accent, .19) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 3
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 7
            anchors.bottomMargin: 7
            width: 3
            radius: 1.5
            color: card.accent
        }
    }

    contentItem: RowLayout {
        spacing: 9

        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: 8
            color: card.accent
            Accessible.ignored: true

            DashboardIcon {
                anchors.centerIn: parent
                width: 21
                height: 21
                symbol: card.symbol
                ink: MaterialTheme.contrastInk(card.accent)
                bold: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                Layout.fillWidth: true
                text: card.headline
                textFormat: Text.PlainText
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: card.ink
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: card.summary
                textFormat: Text.PlainText
                font.pixelSize: 12
                color: card.ink
                wrapMode: Text.WordWrap
            }
        }

        GlassButton {
            objectName: "auralisUpdateCardAction"
            visible: Boolean(card.actionLabel)
            text: card.actionLabel
            Accessible.description: card.headline
            accent: card.accent
            filled: true
            onClicked: card.actionRequested()
        }
    }
}
