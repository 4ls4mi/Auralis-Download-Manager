import QtQuick
import QtQuick.Controls

ToolTip {
    id: tip

    contentItem: Text {
        text: tip.text
        textFormat: Text.PlainText
        font: tip.font
        wrapMode: Text.Wrap
        color: tip.palette.toolTipText
    }
}
