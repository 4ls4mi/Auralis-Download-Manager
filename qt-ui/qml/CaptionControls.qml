pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

RowLayout {
    id: root

    property string material: MaterialTheme.current
    readonly property var colors: MaterialTheme.profile(material)
    property bool trayEnabled: false
    property bool maximized: false
    property string closeLabel: qsTr("Close")
    property string minimizeLabel: qsTr("Minimize")
    signal hideRequested()
    signal minimizeRequested()
    signal maximizeRequested()
    signal closeRequested()

    readonly property var classic: colors.mdm
    readonly property string style: colors.mdmCaptionStyle || "system"
    readonly property color inactiveCaption: classic?.captionInactive || "transparent"
    readonly property color titleFace: classic && !colors.titleOverride && !Window.window?.active && inactiveCaption.a > 0
        ? inactiveCaption : colors.roleFaces?.title || colors.background
    readonly property var metric: ({
        system:  {width: 42, face: 0, height: 28, radius: 0},
        metro:   {width: 42, face: 0, height: 28, radius: 0},
        adwaita: {width: 30, face: 24, height: 24, radius: 12},
        breeze:  {width: 26, face: 18, height: 18, radius: 9},
        luna:    {width: 23, face: 21, height: 21, radius: 3},
        aero:    {width: 27, face: 0, height: 20, radius: 4},
        aqua:    {width: 23, face: 16, height: 16, radius: 8}
    })[style] || {width: 42, face: 0, height: 28, radius: 0}

    spacing: !classic ? 4 : style === "adwaita" || style === "breeze" ? 2 : 0

    component CaptionButton: GlassButton {
        id: button

        required property string symbol

        material: root.material
        readonly property bool dismissButton: symbol === "close"
        readonly property bool shapedButton: root.style === "luna" || root.style === "aero"
            || (root.style === "aqua" && symbol !== "tray")
        readonly property bool engaged: enabled && (hovered || down || visualFocus)
        readonly property color classicFill: {
            const tones = root.classic
            if (!tones || !enabled)
                return "transparent"
            if (shapedButton) {
                const plate = dismissButton && (root.style !== "aqua" || engaged)
                    ? tones.captionClose || root.colors.destructive : tones.captionButton || root.colors.buttonFace || root.colors.background
                return down ? MaterialTheme.mix(plate, root.colors.shade, .20, 1)
                    : engaged ? MaterialTheme.mix(plate, root.colors.upper, .20, 1) : plate
            }
            if (dismissButton && engaged)
                return down ? MaterialTheme.mix(tones.captionClose || root.colors.destructive, root.colors.shade, .13, 1)
                    : tones.captionClose || root.colors.destructive
            if (engaged)
                return down ? tones.captionPressed || Qt.alpha(root.colors.ink, .20)
                    : tones.captionHot || Qt.alpha(root.colors.ink, .12)
            return root.style === "adwaita" ? tones.captionButton || Qt.alpha(root.colors.ink, .10) : "transparent"
        }
        readonly property color classicFace: MaterialTheme.mix(root.titleFace, classicFill, classicFill.a, 1)
        readonly property color classicInk: {
            const tones = root.classic
            const preferred = !enabled || !Window.window?.active ? root.colors.titleMuted || root.colors.muted
                : dismissButton && engaged && tones?.captionCloseText ? tones.captionCloseText
                : root.style === "breeze" && engaged ? root.titleFace : root.colors.titleInk || root.colors.ink
            return MaterialTheme.controlIconInk(preferred, classicFace)
        }

        Layout.preferredWidth: !root.classic ? 35 : root.style === "aero" && dismissButton ? 46 : root.metric.width
        Layout.preferredHeight: root.classic ? 28 : 30
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        Accessible.name: text
        ToolTip.visible: hovered
        ToolTip.delay: 350
        ToolTip.text: text

        Binding {
            target: button.background
            property: "visible"
            value: !root.classic
            when: Boolean(button.background)
        }

        contentItem: Item {
            implicitWidth: 22
            implicitHeight: 22
            transform: Translate { y: button.faceOffset }
            Rectangle {
                id: classicPlate
                visible: Boolean(root.classic) && (color.a > 0 || button.visualFocus)
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.style === "aero" ? 0 : (parent.height - height) / 2
                width: root.metric.face || parent.width
                height: root.metric.height
                radius: root.metric.radius
                color: button.classicFill
                border.width: button.visualFocus || button.shapedButton ? 1 : 0
                border.color: button.visualFocus ? MaterialTheme.controlIconInk(
                    root.classic?.focusRing || root.colors.accent, button.classicFace)
                    : MaterialTheme.mix(button.classicFace, root.colors.ink, .25, 1)
                gradient: button.shapedButton ? classicGloss : null

                Gradient {
                    id: classicGloss
                    GradientStop { position: 0; color: MaterialTheme.mix(button.classicFace, root.colors.upper, .30, 1) }
                    GradientStop { position: .47; color: button.classicFace }
                    GradientStop { position: 1; color: MaterialTheme.mix(button.classicFace, root.colors.shade, .16, 1) }
                }
            }
            DashboardIcon {
                anchors.centerIn: parent
                width: root.classic ? 16 : 22
                height: width
                symbol: button.symbol
                bold: true
                relief: button.enabled
                ink: root.classic ? button.classicInk : button.iconInk
                surface: button.faceColor
            }
        }
    }

    CaptionButton {
        objectName: "hideToTrayCaption"
        visible: root.trayEnabled
        symbol: "tray"
        text: qsTr("Hide to system tray")
        accent: MaterialTheme.actionColor("tray", root.colors.light)
        onClicked: root.hideRequested()
    }
    CaptionButton {
        objectName: "minimizeCaption"
        symbol: "minimize"
        text: root.minimizeLabel
        accent: MaterialTheme.actionColor("minimize", root.colors.light)
        onClicked: root.minimizeRequested()
    }
    CaptionButton {
        objectName: "maximizeCaption"
        symbol: root.maximized ? "restore" : "maximize"
        text: root.maximized ? qsTr("Restore window") : qsTr("Maximize")
        accent: MaterialTheme.actionColor("maximize", root.colors.light)
        onClicked: root.maximizeRequested()
    }
    CaptionButton {
        objectName: "closeCaption"
        symbol: "close"
        text: root.closeLabel
        accent: root.colors.destructive
        onClicked: root.closeRequested()
    }
}
