pragma Singleton

import QtQml

QtObject {
    readonly property int percent: typeof typography === "undefined" ? 100 : typography.fontSizePercent

    function pixels(base) {
        return Math.max(1, Math.round(base * percent / 100))
    }
}
