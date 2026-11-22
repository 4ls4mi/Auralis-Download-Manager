pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

Basic.Menu {
    id: menu

    readonly property var colors: MaterialTheme.menuColors

    popupType: Popup.Item
    focus: true
    margins: 7
    padding: 5
    overlap: 4
    palette.window: colors.surface
    palette.windowText: colors.ink
    palette.text: colors.ink
    palette.dark: colors.border
    palette.highlight: colors.highlight
    palette.highlightedText: colors.highlightInk

    delegate: AppMenuItem { symbol: subMenu ? "queue" : "" }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: MaterialTheme.reducedMotion ? 0 : 135
            easing.type: Easing.OutCubic
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: MaterialTheme.reducedMotion ? 0 : 90
        }
    }

    background: Rectangle {
        implicitWidth: 230
        radius: menu.colors.studio ? 12 : 10
        color: menu.colors.surface
        border.color: menu.colors.border
        border.width: 1
    }
}
