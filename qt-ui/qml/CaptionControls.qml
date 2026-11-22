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
            implicitWidth: 21
            implicitHeight: 21
            DashboardIcon {
                anchors.centerIn: parent
                width: 21
                height: 21
                symbol: button.symbol
                ink: button.accentFill ? button.fillInk : button.displayAccent
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
