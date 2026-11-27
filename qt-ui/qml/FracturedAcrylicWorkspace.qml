pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import "FracturedAcrylicGeometry.js" as Geometry
import "TransferData.js" as Transfer

Item {
    id: root

    required property var download
    required property var downloads
    required property var telemetry
    required property var samples
    required property Action addAction
    property bool online: false
    property bool busy: false
    property bool trayEnabled: false
    property bool automaticUpdateInstall: false
    property bool updatesSupported: false
    property real speed: 0
    property string statusMessage: ""
    property string minimizeLabel: qsTr("Minimize")
    property string closeLabel: qsTr("Close")
    signal selected(string downloadId)
    signal transferRequested(string operation, var download)
    signal detailsRequested(var downloadId)
    signal queueRequested()
    signal settingsRequested(string category)
    signal updateCheckRequested()
    signal automaticUpdateInstallRequested(bool enabled)
    signal hideRequested()
    signal minimizeRequested()
    signal maximizeRequested()
    signal closeRequested()

    readonly property var hostWindow: Window.window
    readonly property var colors: MaterialTheme.palette
    readonly property bool activeTransfer: download?.status === "Downloading"
    readonly property bool completeTransfer: download?.status === "Complete"
    readonly property real fraction: Transfer.fraction(download)
    readonly property var connections: Transfer.connectionCounts(telemetry)
    readonly property var fileList: downloads || []
    readonly property int downloadIndex: fileList.findIndex(file => String(file.id) === String(download?.id ?? ""))
    readonly property string queueStatus: {
        const active = fileList.filter(file => file.status === "Downloading").length
        const queued = fileList.filter(file => file.status === "Queued").length
        return qsTr("%1 active · %2 queued").arg(active).arg(queued)
    }
    readonly property var finishes: [
        { key: "clear", label: qsTr("Clear"), top: "#bda8d4", bottom: "#4b3b5b", translucency: .67, tint: "#a485bc", strength: .14 },
        { key: "acrylic", label: qsTr("Acrylic"), top: "#b19ac8", bottom: "#685477", translucency: .53, tint: "#8f6cb0", strength: .24 },
        { key: "mica", label: qsTr("Mica"), top: "#ddcadf", bottom: "#8e699d", translucency: .26, tint: "#ad839d", strength: .30 },
        { key: "blurred", label: qsTr("Blurred"), top: "#b096c5", bottom: "#54436d", translucency: .47, tint: "#70638e", strength: .33 },
        { key: "frosted", label: qsTr("Frosted"), top: "#bed9df", bottom: "#708797", translucency: -1, tint: "#716085", strength: 0 },
        { key: "smoked", label: qsTr("Smoked"), top: "#866d98", bottom: "#2f233b", translucency: .31, tint: "#27192f", strength: .51 }
    ]
    readonly property string selectedFinish: {
        const current = finishes.find(finish => Math.abs(MaterialTheme.translucency - finish.translucency) < .005
            && Math.abs(MaterialTheme.tintStrength - finish.strength) < .005
            && (finish.strength === 0 || Qt.colorEqual(MaterialTheme.tintColor, finish.tint)))
        return current?.key || ""
    }

    function chooseFinish(finish) {
        MaterialTheme.tintColor = finish.tint
        MaterialTheme.tintStrength = finish.strength
        MaterialTheme.translucency = finish.translucency
    }

    function faceFor(shard) {
        const roles = { header: "title", menu: "title", main: "content", playback: "card",
            effects: "connections", appearance: "sidebar", output: "footer" }
        return MaterialTheme.tint(colors.roleFaces?.[roles[shard]] || colors.background, 1)
    }

    component PanelText: Label {
        color: root.colors.ink
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }

    component PanelHeading: Row {
        id: panelHeading
        required property string title
        required property string symbol
        spacing: 12
        height: 35

        DashboardIcon {
            width: 27
            height: width
            anchors.verticalCenter: parent.verticalCenter
            ink: root.colors.ink
            symbol: panelHeading.symbol
            Accessible.ignored: true
        }
        PanelText {
            width: Math.max(0, parent.width - 39)
            height: parent.height
            text: panelHeading.title
            font.pixelSize: TypographyScale.pixels(27)
            font.weight: Font.DemiBold
            Accessible.role: Accessible.Heading
        }
    }

    component TextAction: Basic.Button {
        id: actionButton

        property int textAlignment: Text.AlignLeft
        hoverEnabled: true
        font.pixelSize: TypographyScale.pixels(20)
        horizontalPadding: 4
        verticalPadding: 2
        contentItem: PanelText {
            text: actionButton.text
            font: actionButton.font
            horizontalAlignment: actionButton.textAlignment
            color: actionButton.hovered || actionButton.visualFocus ? root.colors.accent : root.colors.ink
        }
        background: Rectangle {
            radius: 4
            color: actionButton.down ? Qt.alpha(root.colors.accent, .14) : "transparent"
            border.color: root.colors.accent
            border.width: actionButton.visualFocus ? 2 : 0
        }
    }

    component TitleDragArea: Item {
        DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) root.hostWindow?.startSystemMove()
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: root.maximizeRequested()
        }
    }

    // Use one reference-space transform for all seven shards, so neighboring seams scale together.
    Item {
        id: drawing
        width: 1325
        height: 795
        x: (root.width - width * scale) / 2
        y: (root.height - height * scale) / 2
        scale: Math.min(root.width / width, root.height / height)
        transformOrigin: Item.TopLeft
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Item {
            id: reference
            x: -20
            y: -43
            width: 1345
            height: 838

            Repeater {
                model: ["header", "menu", "main", "playback", "effects", "appearance", "output"]

                FracturedAcrylicShape {
                    required property string modelData
                    readonly property var area: Geometry.bounds[modelData]
                    shard: modelData
                    x: area.x
                    y: area.y
                    width: area.width
                    height: area.height
                    face: root.faceFor(shard)
                }
            }

            TitleDragArea { x: 76; y: 83; width: 783; height: 60 }
            TitleDragArea { x: 1112; y: 94; width: 32; height: 39 }

            BrandMark { x: 85; y: 103; width: 42; height: 42 }
            PanelText {
                x: 142; y: 88; width: 405; height: 46
                text: qsTr("Auralis")
                font.pixelSize: TypographyScale.pixels(37)
                font.weight: Font.Bold
                Accessible.role: Accessible.Heading
            }
            PanelText {
                x: 144; y: 132; width: 340; height: 24
                text: qsTr("Download Manager")
                color: root.colors.muted
                font.pixelSize: TypographyScale.pixels(21)
            }
            TextAction {
                x: 617; y: 105; width: 233; height: 34
                text: qsTr("Browser integration")
                onClicked: root.settingsRequested("Browser Integration")
            }

            GlassButton {
                objectName: "acrylicNewUrl"
                x: 955; y: 87; width: 161; height: 46
                action: root.addAction
                text: qsTr("New URL")
                filled: true
                font.pixelSize: TypographyScale.pixels(23)
                font.weight: Font.DemiBold
                contentItem: RowLayout {
                    spacing: 7
                    DashboardIcon {
                        symbol: "add"
                        ink: root.colors.shade
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        bold: true
                        Accessible.ignored: true
                    }
                    PanelText {
                        Layout.fillWidth: true
                        text: qsTr("New URL")
                        color: root.colors.shade
                        font.pixelSize: TypographyScale.pixels(23)
                        font.weight: Font.DemiBold
                        Accessible.ignored: true
                    }
                }
            }

            CaptionControls {
                x: 1144; y: 90; width: 158; height: 44
                trayEnabled: root.trayEnabled
                maximized: root.hostWindow?.visibility === Window.Maximized
                minimizeLabel: root.minimizeLabel
                closeLabel: root.closeLabel
                onHideRequested: root.hideRequested()
                onMinimizeRequested: root.minimizeRequested()
                onMaximizeRequested: root.maximizeRequested()
                onCloseRequested: root.closeRequested()
            }

            PanelText {
                x: 110; y: 216; width: 327; height: 33
                visible: Boolean(root.download)
                text: Transfer.statusLabel(root.download?.status)
                font.pixelSize: TypographyScale.pixels(23)
                color: root.activeTransfer ? root.colors.positive : root.colors.muted
                horizontalAlignment: Text.AlignHCenter
            }
            PanelText {
                x: 98; y: 252; width: 348; height: 48
                text: root.download?.file || (root.online ? qsTr("No downloads yet") : qsTr("Connecting to Auralis…"))
                font.pixelSize: TypographyScale.pixels(31)
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                Accessible.role: Accessible.Heading
            }

            Basic.ProgressBar {
                id: dial
                x: 138; y: 302; width: 270; height: 208
                value: root.fraction
                visible: Boolean(root.download)
                Accessible.name: qsTr("File progress")
                contentItem: Item {}
                background: Shape {
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(root.colors.ink, .18)
                        strokeWidth: 15
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 135; centerY: 134; radiusX: 115; radiusY: 115; startAngle: 153; sweepAngle: 234 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.fraction > 0 ? root.colors.positive : "transparent"
                        strokeWidth: 15
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 135; centerY: 134; radiusX: 115; radiusY: 115
                            startAngle: 153
                            sweepAngle: 234 * root.fraction
                        }
                    }
                }
                NumeralLabel {
                    x: 0; y: 74; width: parent.width; height: 83
                    valueText: qsTr("%1%").arg(Math.floor(dial.value * 100))
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: root.colors.ink
                    font.pixelSize: TypographyScale.pixels(75)
                    font.weight: Font.DemiBold
                    Accessible.ignored: true
                }
                NumeralLabel {
                    x: 0; y: 154; width: parent.width; height: 29
                    valueText: Transfer.bytes(root.download?.size)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: root.colors.muted
                    font.pixelSize: TypographyScale.pixels(23)
                }
            }

            DashboardIcon {
                x: 216; y: 357; width: 112; height: 112
                visible: !root.download
                symbol: "downloads"
                ink: Qt.alpha(root.colors.accent, .62)
                Accessible.ignored: true
            }

            NumeralLabel {
                x: 133; y: 503; width: 280; height: 32
                visible: Boolean(root.download)
                color: root.colors.muted
                font.pixelSize: TypographyScale.pixels(23)
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                valueText: root.completeTransfer ? qsTr("Transfer complete")
                    : Transfer.rate(root.activeTransfer ? root.download?.speed : 0)
            }

            GlassButton {
                x: 142; y: 544; width: 219; height: 51
                visible: Boolean(root.download) && !root.completeTransfer
                enabled: root.online && !root.busy
                text: root.activeTransfer ? qsTr("Pause download")
                    : root.download?.status === "Queued" ? qsTr("Start download") : qsTr("Resume download")
                filled: true
                font.pixelSize: TypographyScale.pixels(22)
                font.weight: Font.DemiBold
                onClicked: root.transferRequested(root.activeTransfer ? "pause" : "start", root.download)
            }
            GlassButton {
                x: 142; y: 517; width: 219; height: 51
                visible: !root.download
                action: root.addAction
                filled: true
                font.pixelSize: TypographyScale.pixels(22)
                font.weight: Font.DemiBold
            }
            TextAction {
                x: 159; y: root.completeTransfer ? 553 : 601; width: 185; height: 36
                visible: Boolean(root.download)
                text: qsTr("Download details")
                textAlignment: Text.AlignHCenter
                onClicked: root.detailsRequested(root.download.id)
            }

            PanelHeading {
                x: 603; y: 234; width: 260
                title: qsTr("Download queue"); symbol: "queue"
            }
            GlassComboBox {
                objectName: "acrylicDownloadQueue"
                x: 601; y: 285; width: 259; height: 56
                model: root.fileList
                textRole: "file"
                valueRole: "id"
                currentIndex: root.downloadIndex
                enabled: root.fileList.length > 0
                displayText: enabled ? currentText : qsTr("No downloads yet")
                font.pixelSize: TypographyScale.pixels(22)
                Accessible.name: qsTr("Selected download")
                onActivated: index => root.selected(String(valueAt(index)))
            }
            PanelText {
                x: 602; y: 348; width: 145; height: 32
                text: root.queueStatus
                color: root.colors.muted
                font.pixelSize: TypographyScale.pixels(18)
            }
            TextAction {
                x: 749; y: 348; width: 99; height: 32
                text: qsTr("Open queue")
                font.pixelSize: TypographyScale.pixels(18)
                onClicked: root.queueRequested()
            }

            PanelHeading {
                x: 542; y: 467; width: 267
                title: qsTr("Connections"); symbol: "activity"
            }
            NumeralLabel {
                x: 543; y: 514; width: 123; height: 49
                valueText: qsTr("%1 / %2").arg(root.connections.active).arg(root.connections.configured)
                color: root.colors.ink
                font.pixelSize: TypographyScale.pixels(40)
                font.weight: Font.DemiBold
                verticalAlignment: Text.AlignVCenter
                Accessible.name: qsTr("%1 active of %2 configured connections")
                    .arg(root.connections.active).arg(root.connections.configured)
            }
            PanelText {
                x: 666; y: 522; width: 154; height: 36
                text: qsTr("Active / configured")
                color: root.colors.muted
                font.pixelSize: TypographyScale.pixels(19)
            }
            ConnectionSlotGrid {
                x: 543; y: 576; width: 268; height: 18
                activeCount: root.connections.active
                configuredCount: root.connections.configured
                activeInk: root.colors.positive
            }
            PanelText {
                x: 568; y: 613; width: 244; height: 48
                visible: text.length > 0
                text: root.statusMessage
                color: root.colors.caution
                font.pixelSize: TypographyScale.pixels(17)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                Accessible.name: text
                ToolTip.visible: statusHover.hovered && truncated
                ToolTip.delay: 400
                ToolTip.text: text
                HoverHandler { id: statusHover }
                onTextChanged: if (visible) Accessible.announce(text)
            }
            MouseArea {
                id: resizeGrip
                objectName: "acrylicResizeGrip"
                x: 811; y: 646; width: 48; height: 46
                visible: root.hostWindow?.visibility === Window.Windowed
                hoverEnabled: true
                cursorShape: Qt.SizeFDiagCursor
                Accessible.ignored: true
                onPressed: root.hostWindow?.startSystemResize(Qt.RightEdge | Qt.BottomEdge)

                Repeater {
                    model: [
                        [34, 6], [34, 15], [34, 24], [34, 33],
                        [25, 15], [25, 24], [25, 33],
                        [16, 24], [16, 33], [7, 33]
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData[0]; y: modelData[1]; width: 3.2; height: width
                        radius: width / 2
                        color: resizeGrip.containsMouse ? root.colors.accent : Qt.alpha(root.colors.ink, .69)
                    }
                }
            }

            PanelHeading {
                x: 944; y: 226; width: 285
                title: qsTr("Appearance"); symbol: "app"
            }
            Grid {
                x: 946; y: 278; columns: 3; spacing: 10
                Repeater {
                    model: root.finishes
                    delegate: Basic.Button {
                        id: swatch
                        required property var modelData
                        readonly property bool chosen: root.selectedFinish === modelData.key
                        width: 92; height: 91
                        text: modelData.label
                        hoverEnabled: true
                        Accessible.name: text
                        Accessible.checkable: true
                        Accessible.checked: chosen
                        onClicked: root.chooseFinish(modelData)
                        background: Rectangle {
                            radius: 13
                            color: swatch.chosen || swatch.hovered
                                ? Qt.alpha(root.colors.accent, swatch.down ? .19 : .11) : Qt.alpha(root.colors.ink, .035)
                            border.color: swatch.chosen || swatch.visualFocus ? root.colors.accent : Qt.alpha(root.colors.ink, .3)
                            border.width: swatch.chosen || swatch.visualFocus ? 2 : 1
                        }
                        contentItem: Item {
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 5; width: 41; height: 40
                                radius: 7
                                border.color: Qt.alpha(root.colors.ink, .38)
                                gradient: Gradient {
                                    GradientStop { position: 0; color: swatch.modelData.top }
                                    GradientStop { position: 1; color: swatch.modelData.bottom }
                                }
                                Accessible.ignored: true
                            }
                            PanelText {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 26
                                text: swatch.text
                                color: swatch.chosen ? root.colors.accent : root.colors.ink
                                font.pixelSize: TypographyScale.pixels(20)
                                horizontalAlignment: Text.AlignHCenter
                                Accessible.ignored: true
                            }
                        }
                    }
                }
            }

            Rectangle { x: 946; y: 501; width: 298; height: 1; color: Qt.alpha(root.colors.ink, .28) }
            PanelHeading {
                x: 944; y: 517; width: 287
                title: qsTr("Updates"); symbol: "refresh"
            }
            PanelText {
                x: 946; y: 560; width: 242; height: 42
                visible: root.updatesSupported
                text: qsTr("Install updates automatically")
                font.pixelSize: TypographyScale.pixels(20)
            }
            GlassSwitch {
                x: 1186; y: 560; width: 61; height: 42
                objectName: "acrylicAutomaticUpdateInstall"
                visible: root.updatesSupported
                checked: root.automaticUpdateInstall
                Accessible.name: qsTr("Install updates automatically")
                onToggled: root.automaticUpdateInstallRequested(checked)
            }
            Rectangle {
                x: 946; y: 612; width: 296; height: 1
                visible: root.updatesSupported
                color: Qt.alpha(root.colors.ink, .28)
            }
            TextAction {
                x: 946; y: root.updatesSupported ? 623 : 558; width: 286; height: 35
                text: root.updatesSupported ? qsTr("Check for updates") : qsTr("Updates & about")
                onClicked: root.updatesSupported ? root.updateCheckRequested() : root.settingsRequested("Updates")
            }
            TextAction {
                x: 946; y: root.updatesSupported ? 662 : 604; width: 184; height: 35
                text: qsTr("Appearance settings")
                onClicked: root.settingsRequested("Appearance")
            }

            PanelHeading {
                x: 123; y: 726; width: 204
                title: qsTr("Transfer speed"); symbol: "activity"
            }
            NumeralLabel {
                x: 163; y: 760; width: 164; height: 35
                valueText: Transfer.rate(root.speed)
                color: root.colors.ink
                font.pixelSize: TypographyScale.pixels(30)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            TransferGraph {
                x: 334; y: 735; width: 180; height: 55
                samples: (root.samples || []).slice(-11)
                compactStyle: true
                graphShape: "bars"
                animationStyle: WindowAppearance.graphAnimation
                flowActive: root.speed > 0
                lineColor: root.colors.positive
                endpointColor: root.colors.accent
                Accessible.name: qsTr("Recent total transfer speed")
            }
        }
    }
}
