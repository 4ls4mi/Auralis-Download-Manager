pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Label {
    id: root

    required property string valueText
    readonly property string formattedNumerals: typeof typography === "undefined"
        ? "" : typography?.numeralMarkup?.(valueText, font.family) || ""

    text: formattedNumerals || valueText
    textFormat: formattedNumerals ? Text.RichText : Text.PlainText
    clip: Boolean(formattedNumerals)
    Accessible.name: valueText
}
