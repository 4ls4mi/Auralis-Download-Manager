pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "TransferData.js" as TransferData

Frame {
    id: card

    property string stage: "available"
    property string installedVersion
    property string targetVersion
    property double installerBytes: 0
    property double downloadedBytes: -1
    property string problem
    property string actionLabel
    property bool announceChanges: false
    property bool fractured: false
    readonly property var colors: MaterialTheme.palette
    readonly property bool hasProgress: downloadedBytes >= 0 && installerBytes > 0
    readonly property real completion: hasProgress ? Math.min(1, downloadedBytes / installerBytes) : 0
    readonly property string headline: {
        switch (stage) {
        case "checking": return qsTr("Checking for updates…")
        case "rechecking": return qsTr("Confirming Auralis %1…").arg(targetVersion)
        case "connecting": return qsTr("Connecting to download Auralis %1…").arg(targetVersion)
        case "downloading": return qsTr("Downloading Auralis %1…").arg(targetVersion)
        case "verifying": return qsTr("Verifying the Auralis %1 installer…").arg(targetVersion)
        case "waiting": return qsTr("Auralis %1 is ready and will install when downloads are idle").arg(targetVersion)
        case "installing": return qsTr("Starting the Auralis %1 installer…").arg(targetVersion)
        case "closing": return qsTr("Closing Auralis to install %1…").arg(targetVersion)
        case "latest": return qsTr("Auralis is up to date")
        case "error": return targetVersion ? qsTr("Auralis update could not finish") : qsTr("Update check unavailable")
        default: return qsTr("Auralis %1 is available").arg(targetVersion)
        }
    }
    readonly property string summary: {
        if (hasProgress)
            return qsTranslate("UpdateWindow", "%1% · %2 of %3").arg(Math.floor(completion * 100))
                .arg(TransferData.bytes(downloadedBytes)).arg(TransferData.bytes(installerBytes))
        return installerBytes > 0 && targetVersion
            ? qsTr("Installed %1 · %2 installer").arg(installedVersion).arg(TransferData.bytes(installerBytes))
            : qsTr("Installed version %1").arg(installedVersion)
    }
    readonly property string symbol: stage === "latest" ? "complete" : stage === "error" ? "details"
        : stage === "checking" || stage === "rechecking" ? "refresh" : "downloads"
    readonly property color accent: MaterialTheme.vividControlAccent(MaterialTheme.actionColor(stage === "error" ? "pause"
        : stage === "checking" || stage === "rechecking" || stage === "verifying" ? "clock" : "add", colors.light), colors.light)
    readonly property color ground: MaterialTheme.mix(colors.background, colors.light ? "#ffffff" : "#050817", .22, 1)
    readonly property color face: MaterialTheme.mix(ground, accent, colors.light ? .17 : .25, 1)
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

    background: Item {
        Loader {
            anchors.fill: parent
            active: card.fractured
            sourceComponent: FracturedPanel {
                edge: "banner"
                face: card.face
                forceOpaque: true
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: !card.fractured
            radius: 9
            color: card.face
            border.width: 1
            border.color: MaterialTheme.mix(card.colors.edge, card.accent, .76, 1)
        }

        Item {
            anchors.fill: parent
            anchors.margins: card.fractured ? 5 : 2
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
            gradient: Gradient {
                GradientStop { position: 0; color: MaterialTheme.mix(card.accent, "#ffffff", .12, 1) }
                GradientStop { position: .45; color: card.accent }
                GradientStop { position: 1; color: MaterialTheme.mix(card.accent, "#152035", .24, 1) }
            }
            Accessible.ignored: true

            DashboardIcon {
                anchors.centerIn: parent
                width: 21
                height: 21
                symbol: card.symbol
                relief: card.enabled
                surface: card.accent
                ink: MaterialTheme.mix(MaterialTheme.contrastInk(card.accent), card.accent, .15, 1)
                bold: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            NumeralLabel {
                Layout.fillWidth: true
                valueText: card.headline
                font.pixelSize: TypographyScale.pixels(15)
                font.weight: Font.DemiBold
                color: card.ink
                wrapMode: Text.WordWrap
            }
            NumeralLabel {
                Layout.fillWidth: true
                valueText: card.summary
                font.pixelSize: TypographyScale.pixels(12)
                color: card.ink
                wrapMode: Text.WordWrap
            }
            GlassProgress {
                objectName: "updateCardDownloadProgress"
                Layout.fillWidth: true
                baseHeight: 11
                visible: card.hasProgress
                value: card.completion
                animated: visible && card.Window.visibility !== Window.Minimized
                layoutStyle: "classic"
                animationStyle: WindowAppearance.progressAnimation
                shape: WindowAppearance.progressShape === "material"
                    ? (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.progressShape
                startColor: MaterialTheme.progressColors[0]
                endColor: MaterialTheme.progressColors[1]
                showLabel: false
                Accessible.ignored: true
            }
            Label {
                Layout.fillWidth: true
                visible: Boolean(card.problem)
                text: card.problem
                textFormat: Text.PlainText
                font.pixelSize: TypographyScale.pixels(12)
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
