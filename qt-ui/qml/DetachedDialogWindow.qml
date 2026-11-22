pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root

    property Window hostWindow
    property string material: MaterialTheme.current
    readonly property var colors: MaterialTheme.profile(material)
    property bool busy: false
    property bool positioned: false
    property int innerPadding: 16
    property alias bodyContent: body.data
    readonly property int preferredHeight: Math.ceil(Math.max(minimumHeight,
        Math.min(650, body.implicitHeight + header.implicitHeight
                 + (footer && footer.visible ? footer.implicitHeight : 0) + 2 * innerPadding)))
    property size fittedSize
    property bool userResized: false

    signal opened()
    signal dismissed()
    signal dismissRequested()

    width: 510
    minimumWidth: 365
    minimumHeight: 155
    height: minimumHeight
    color: "transparent"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
    transientParent: hostWindow && hostWindow.visible && hostWindow.visibility !== Window.Minimized ? hostWindow : null
    modality: Qt.WindowModal
    palette.window: colors.background
    palette.windowText: colors.ink
    palette.base: colors.background
    palette.text: colors.ink
    palette.buttonText: colors.ink
    palette.highlight: colors.accent
    palette.placeholderText: colors.muted

    function fitInitialHeight() {
        if (userResized)
            return
        if (fittedSize.width > 0 && (width !== fittedSize.width || height !== fittedSize.height)) {
            userResized = true
            return
        }
        fittedSize = Qt.size(width, preferredHeight)
        height = fittedSize.height
    }

    function open() {
        if (!visible)
            fitInitialHeight()
        if (!visible && !positioned) {
            if (transientParent) {
                x = Math.round(transientParent.x + (transientParent.width - width) / 2)
                y = Math.round(transientParent.y + (transientParent.height - height) / 2)
            }
            positioned = true
        }
        show()
        raise()
        requestActivate()
    }

    onPreferredHeightChanged: if (visible) Qt.callLater(fitInitialHeight)
    onVisibleChanged: {
        if (visible)
            opened()
        else
            dismissed()
    }
    onClosing: event => {
        event.accepted = false
        if (!busy)
            dismissRequested()
    }

    background: Loader {
        active: root.visible
        sourceComponent: WindowBackdrop {
            hostWindow: root
            target: "details"
        }
    }

    header: Item {
        implicitHeight: Math.max(dialogBrand.implicitHeight, heading.implicitHeight) + 20
        GlassSurface { anchors.fill: parent; material: root.material; role: "title" }
        BrandMark {
            id: dialogBrand
            anchors.left: parent.left
            anchors.leftMargin: root.innerPadding
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            id: heading
            anchors.left: dialogBrand.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: root.innerPadding
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            text: root.title
            color: root.colors.ink
            font.bold: true
            font.pixelSize: 18
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: root.innerPadding
        contentWidth: availableWidth
        contentHeight: body.implicitHeight
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            id: grip
            policy: ScrollBar.AsNeeded
            implicitWidth: 7
            padding: 1
            contentItem: Rectangle {
                implicitWidth: 5
                radius: 2.5
                color: root.colors.secondary
                opacity: grip.active ? .85 : .58
            }
            background: Item {}
        }
        ColumnLayout {
            id: body
            width: scroll.availableWidth
            spacing: 9
        }
    }

    WindowResizeHandles { hostWindow: root }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !root.busy
        onActivated: root.dismissRequested()
    }
}
