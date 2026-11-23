pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window

    readonly property var fontSettings: typeof typography === "undefined" ? null : typography

    Binding on font {
        when: window.fontSettings !== null
        value: window.fontSettings?.interfaceFont
    }

    function fontFamilyForText(text) {
        if (!fontSettings || (!fontSettings.englishFamily && !fontSettings.arabicFamily))
            return font.family
        return fontSettings.fontForText(text).family || font.family
    }
}
