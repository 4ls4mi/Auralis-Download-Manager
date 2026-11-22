pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

DetachedDialogWindow {
    id: root

    property string message: ""
    property string confirmText: qsTr("Confirm")
    property string cancelText: qsTr("Cancel")
    property bool destructive: false
    property bool showOption: false
    property string optionText: ""
    property alias optionChecked: option.checked
    signal confirmed()
    signal cancelled()

    width: 460
    objectName: "detachedConfirmation"

    function cancel() {
        hide()
        cancelled()
    }

    function confirm() {
        if (busy)
            return
        hide()
        confirmed()
    }

    onDismissRequested: cancel()
    onOpened: cancelButton.forceActiveFocus()

    bodyContent: [
        Label {
            Layout.fillWidth: true
            text: root.message
            wrapMode: Text.Wrap
            color: root.colors.ink
            textFormat: Text.PlainText
        },
        CheckBox {
            id: option
            visible: root.showOption
            Layout.fillWidth: true
            text: root.optionText
        }
    ]

    footer: Item {
        implicitHeight: actions.implicitHeight + 20
        GlassSurface { anchors.fill: parent; material: root.material; role: "footer" }
        RowLayout {
            id: actions
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            Item { Layout.fillWidth: true }
            GlassButton {
                id: cancelButton
                material: root.material
                text: root.cancelText
                enabled: !root.busy
                onClicked: root.cancel()
            }
            GlassButton {
                material: root.material
                accent: root.destructive ? root.colors.destructive : root.colors.positive
                text: root.confirmText
                enabled: !root.busy
                onClicked: root.confirm()
            }
        }
    }
}
