pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

AuralisWindow {
    id: root

    property Window hostWindow
    property string material: MaterialTheme.current
    readonly property var colors: MaterialTheme.profile(material)
    property bool busy: false
    property bool positioned: false
    property bool customFrame: false
    property int customFrameWindowType: Qt.Dialog
    property int innerPadding: 16
    readonly property int captionInset: Math.max(innerPadding, frameSafeInset)
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
    frameShapingEnabled: customFrame
    flags: customFrame
        ? customFrameWindowType | Qt.FramelessWindowHint | Qt.WindowSystemMenuHint | Qt.WindowMinMaxButtonsHint | Qt.WindowCloseButtonHint
        : Qt.Dialog | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
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
        if (customFrame && visibility === Window.Minimized)
            showNormal()
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

    function toggleMaximized() {
        if (visibility === Window.Maximized)
            showNormal()
        else
            showMaximized()
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
        implicitHeight: Math.max(dialogBrand.implicitHeight, heading.implicitHeight,
                                 controls.visible ? controls.implicitHeight : 0) + 20
        GlassSurface { anchors.fill: parent; material: root.material; role: "title" }
        BrandMark {
            id: dialogBrand
            anchors.left: parent.left
            anchors.leftMargin: root.captionInset
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            id: heading
            anchors.left: dialogBrand.right
            anchors.leftMargin: 8
            anchors.right: controls.visible ? controls.left : parent.right
            anchors.rightMargin: controls.visible ? 8 : root.innerPadding
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            text: root.title
            color: root.colors.ink
            font.family: root.fontFamilyForText(text)
            font.bold: true
            font.pixelSize: TypographyScale.pixels(18)
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        CaptionMoveArea {
            objectName: "detachedCaptionMoveArea"
            anchors.left: parent.left
            anchors.right: controls.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: root.customFrame
            hostWindow: root
            allowManualMove: true
            onDoubleClickRequested: root.toggleMaximized()
        }
        CaptionControls {
            id: controls
            anchors.right: parent.right
            anchors.rightMargin: root.captionInset
            anchors.verticalCenter: parent.verticalCenter
            visible: root.customFrame
            material: root.material
            maximized: root.visibility === Window.Maximized
            onMinimizeRequested: root.showMinimized()
            onMaximizeRequested: root.toggleMaximized()
            onCloseRequested: root.close()
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

    WindowResizeHandles {
        hostWindow: root
        coalesceGeometry: root.customFrame
        showGrip: root.customFrame
        gripColor: root.colors.muted
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !root.busy
        onActivated: root.dismissRequested()
    }
}
