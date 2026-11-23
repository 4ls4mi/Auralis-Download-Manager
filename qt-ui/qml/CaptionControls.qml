pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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

    spacing: 4

    component CaptionButton: GlassButton {
        id: button

        required property string symbol

        material: root.material
        Layout.preferredWidth: 35
        Layout.preferredHeight: 30
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        Accessible.name: text
        ToolTip.visible: hovered
        ToolTip.delay: 350
        ToolTip.text: text

        contentItem: Item {
            implicitWidth: 22
            implicitHeight: 22
            transform: Translate { y: button.faceOffset }
            DashboardIcon {
                anchors.centerIn: parent
                width: 22
                height: 22
                symbol: button.symbol
                bold: true
                relief: button.enabled
                ink: button.iconInk
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
