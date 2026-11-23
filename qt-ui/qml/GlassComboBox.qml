pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts

Basic.ComboBox {
    id: control

    readonly property var colors: MaterialTheme.palette
    property var fontOptionPreview: null
    property var colorOptionPreview: null

    hoverEnabled: true
    font.pixelSize: TypographyScale.pixels(13)
    implicitHeight: Math.max(36, font.pixelSize + 16)

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
        readonly property var swatch: control.colorOptionPreview
            ? control.colorOptionPreview(control.valueAt(index)) : null
        width: ListView.view.width
        implicitHeight: Math.max(32, font.pixelSize + 12)
        text: control.textAt(index)
        highlighted: control.highlightedIndex === index
        hoverEnabled: true
        font: control.font
        contentItem: RowLayout {
            spacing: 7
            layoutDirection: control.mirrored ? Qt.RightToLeft : Qt.LeftToRight

            Rectangle {
                visible: Boolean(option.swatch)
                Layout.preferredWidth: 32
                Layout.preferredHeight: 12
                radius: 3
                border.color: control.colors.divider
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: option.swatch?.[0] ?? "transparent" }
                    GradientStop { position: 1; color: option.swatch?.[1] ?? "transparent" }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: option.text
                font: option.font
                verticalAlignment: Text.AlignVCenter
                color: control.colors.text
                elide: Text.ElideRight
            }
        }
        background: Rectangle {
            radius: 5
            color: option.highlighted || option.hovered
                ? MaterialTheme.rgba(control.colors.accent, .23)
                : "transparent"
        }

        Loader {
            active: control.fontOptionPreview !== null && control.popup.visible && option.hovered
            sourceComponent: Basic.ToolTip {
                id: preview
                readonly property var sample: control.fontOptionPreview(control.valueAt(option.index))
                readonly property point windowPosition: option.mapToItem(option.Window.contentItem, 0, 0)
                readonly property bool fitsRight: windowPosition.x + option.width + width + 14
                    <= (option.Window.window?.width ?? 0)
                readonly property bool fitsLeft: windowPosition.x >= width + 14

                parent: option
                width: Math.min(242, Math.max(120, (option.Window.window?.width ?? 256) - 16))
                x: fitsRight ? option.width + 6 : fitsLeft ? -width - 6 : 0
                y: fitsRight || fitsLeft ? (option.height - height) / 2 : -height - 6
                visible: true
                delay: 180
                timeout: -1
                focus: false
                enabled: false
                z: 20
                padding: 10
                text: sample.text
                font: sample.font
                closePolicy: Basic.Popup.NoAutoClose

                contentItem: Text {
                    text: preview.text
                    font: preview.font
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: control.colors.text
                }
                background: Rectangle {
                    radius: 6
                    color: control.colors.background
                    border.color: control.colors.divider
                }
            }
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
