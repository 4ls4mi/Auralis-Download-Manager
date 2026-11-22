pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.ComboBox {
    id: control

    readonly property var colors: MaterialTheme.palette

    hoverEnabled: true
    font.pixelSize: 13
    implicitHeight: 36

    palette.text: colors.text
    palette.buttonText: colors.text
    palette.base: colors.background
    palette.button: colors.background
    palette.window: colors.background
    palette.windowText: colors.text
    palette.highlight: colors.accent
    palette.highlightedText: colors.background
    palette.dark: colors.muted
    palette.mid: colors.divider

    contentItem: TextInput {
        leftPadding: control.mirrored ? 0 : 10
        rightPadding: control.mirrored ? 10 : 0
        text: control.editable ? control.editText : control.displayText
        color: control.enabled ? control.colors.text : control.colors.muted
        verticalAlignment: TextInput.AlignVCenter
        readOnly: !control.editable
        enabled: control.editable
        clip: true
        validator: control.validator
        inputMethodHints: control.inputMethodHints
        selectByMouse: control.selectTextByMouse
        font: control.font
    }

    indicator: DashboardIcon {
        x: control.mirrored ? 8 : control.width - width - 8
        y: (control.height - height) / 2
        width: 16
        height: 16
        symbol: "chevron"
        ink: control.colors.accent
        bold: true
    }

    delegate: Basic.ItemDelegate {
        id: option
        required property int index
        width: ListView.view.width
        implicitHeight: 32
        text: control.textAt(index)
        highlighted: control.highlightedIndex === index
        hoverEnabled: true
        font: control.font
        contentItem: Text {
            text: option.text
            font: option.font
            verticalAlignment: Text.AlignVCenter
            color: control.colors.text
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 5
            color: option.highlighted || option.hovered
                ? MaterialTheme.rgba(control.colors.accent, .23)
                : "transparent"
        }
    }

    background: Item {
        implicitWidth: 140
        implicitHeight: 36
        GlassSurface { anchors.fill: parent; role: "field" }
        Rectangle {
            anchors.fill: parent
            radius: 5
            color: "transparent"
            border.color: control.visualFocus || control.hovered ? control.colors.accent : control.colors.divider
            border.width: control.visualFocus ? 2 : 1
        }
    }
}
