pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

GridLayout {
    id: root

    required property var backdrop
    readonly property var colors: MaterialTheme.palette
    readonly property bool sideTabs: ["fogSlate", "violetRail", "coralSlate"].includes(colors.layout)
    readonly property var sections: [qsTr("Materials and color"), qsTr("Window backgrounds"), qsTr("Indicators")]
    property int activeTab: 0
    property string fileAction
    property string status
    property bool failed: false
    property bool busy: false
    property real previewPhase: 0
    readonly property bool previewActive: visible && activeTab === 2
        && Boolean(Window.window?.visible) && Window.window.visibility !== Window.Minimized

    NumberAnimation on previewPhase {
        from: 0
        to: Math.PI * 2
        duration: 1350
        loops: Animation.Infinite
        running: root.previewActive && WindowAppearance.connectionAnimation !== "none" && !MaterialTheme.reducedMotion
    }
    readonly property var shapeChoices: [
        {label: qsTr("Material default"), value: "material"}, {label: qsTr("Rounded"), value: "round"},
        {label: qsTr("Square"), value: "square"}, {label: qsTr("Bubble"), value: "bubble"},
        {label: qsTr("Faceted"), value: "prism"}, {label: qsTr("Ice"), value: "ice"}
    ]

    columns: 2
    columnSpacing: sideTabs ? 10 : 0
    rowSpacing: 13

    function report(message, error) {
        status = message
        failed = error
    }

    function save(action) {
        fileAction = action
        outputFile.open()
    }

    function importFile(file) {
        const action = fileAction
        busy = true
        engine.request({local: "readShareFile", file: file}, function(response, error) {
            busy = false
            if (error || !response) {
                report(error || qsTr("Could not read the selected file."), true)
                return
            }
            if (action === "material") {
                const id = MaterialTheme.installMaterial(response)
                if (id) MaterialTheme.current = id
                report(id ? qsTr("Material imported.") : qsTr("Choose a valid Auralis material file."), !id)
            } else {
                const installed = WindowAppearance.importTheme(response)
                report(installed ? qsTr("Theme imported.") : qsTr("Choose a valid Auralis theme file."), !installed)
            }
        })
    }

    component Tile: Frame {
        Layout.fillWidth: true
        padding: 14
        background: GlassSurface { role: "content"; backdropAvailable: root.backdrop.backdropAvailable }
    }

    component TabPage: Tile {
        property int pageRow: 0

        Layout.column: root.sideTabs ? 1 : 0
        Layout.columnSpan: root.sideTabs ? 1 : 2
        Layout.row: pageRow + (root.sideTabs ? 0 : 1)
        Layout.minimumWidth: 0
    }

    component Heading: Label {
        Layout.fillWidth: true
        color: root.colors.text
        font.pixelSize: TypographyScale.pixels(17)
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    component Choice: GlassComboBox {
        id: choice

        required property string selection

        Layout.fillWidth: true
        textRole: "label"
        valueRole: "value"
        currentIndex: (model || []).findIndex(option => option.value === choice.selection)
    }

    component IndicatorChoice: ColumnLayout {
        id: field

        required property string label
        required property string selection
        property alias model: control.model
        property alias colorOptionPreview: control.colorOptionPreview
        signal chosen(var value)

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 4

        Label {
            Layout.fillWidth: true
            text: field.label
            color: root.colors.text
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
        }

        Choice {
            id: control
            selection: field.selection
            Accessible.name: field.label
            onActivated: field.chosen(currentValue)
        }
    }

    component IndicatorColorChoice: IndicatorChoice {
        id: colorsField
        required property string indicatorRole

        model: MaterialTheme.indicatorChoices
        colorOptionPreview: value => {
            if (typeof value !== "string")
                return null
            const fallback = colorsField.indicatorRole === "connections" ? "ocean" : "blue-purple"
            return MaterialTheme.colorsFor(value,
                MaterialTheme.resolvedPalette(value, fallback, colorsField.indicatorRole), colorsField.indicatorRole)
        }
    }

    TabBar {
        id: topTabs

        visible: !root.sideTabs
        Layout.fillWidth: true
        Layout.column: 0
        Layout.columnSpan: 2
        Layout.row: 0
        currentIndex: root.activeTab
        onCurrentIndexChanged: if (currentIndex >= 0 && root.activeTab !== currentIndex)
            root.activeTab = currentIndex

        Repeater {
            model: root.sections
            delegate: GlassTabButton {
                required property string modelData
                required property int index
                accent: MaterialTheme.navigationColor(index, root.colors.light)
                text: modelData
            }
        }
    }

    ColumnLayout {
        visible: root.sideTabs
        Layout.column: 0
        Layout.row: 0
        Layout.rowSpan: root.activeTab === 1 ? 2 : 1
        Layout.preferredWidth: Math.max(100, Math.min(144, Math.round(root.width * .25)))
        Layout.fillWidth: false
        Layout.alignment: Qt.AlignTop | Qt.AlignLeft
        spacing: 5
        Accessible.role: Accessible.PageTabList
        Accessible.name: qsTr("Appearance sections")

        Repeater {
            id: sideTabButtons
            model: root.sections
            delegate: GlassButton {
                id: tab
                required property int index
                required property string modelData

                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 39
                leftPadding: 8
                rightPadding: 7
                text: modelData
                checked: root.activeTab === index
                accent: MaterialTheme.navigationColor(index, root.colors.light)
                Accessible.role: Accessible.PageTab
                Accessible.selected: checked
                onClicked: root.activeTab = index

                contentItem: Label {
                    text: tab.text
                    font.family: tab.font.family
                    font.pixelSize: tab.font.pixelSize
                    font.weight: tab.checked ? Font.DemiBold : Font.Normal
                    color: tab.buttonInk
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Keys.onPressed: event => {
                    const count = root.sections.length
                    let target = index
                    switch (event.key) {
                    case Qt.Key_Up: target = (index + count - 1) % count; break
                    case Qt.Key_Down: target = (index + 1) % count; break
                    case Qt.Key_Home: target = 0; break
                    case Qt.Key_End: target = count - 1; break
                    default: return
                    }
                    root.activeTab = target
                    sideTabButtons.itemAt(target).forceActiveFocus(Qt.TabFocusReason)
                    event.accepted = true
                }
            }
        }
    }

    TabPage {
        visible: root.activeTab === 0

        ColumnLayout {
            width: parent.width
            spacing: 12
            Heading { text: qsTr("Surface material") }

            GridLayout {
                Layout.fillWidth: true
                columns: Math.max(1, Math.min(4, Math.floor(width / 160)))
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: MaterialTheme.materials
                    delegate: GlassButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 120
                        material: modelData.id
                        text: checked ? qsTr("✓  %1").arg(modelData.name) : modelData.name
                        Accessible.name: modelData.name
                        Accessible.selected: checked
                        checkable: true
                        checked: MaterialTheme.current === modelData.id
                        highlighted: checked
                        onClicked: {
                            MaterialTheme.current = modelData.id
                            checked = Qt.binding(() => MaterialTheme.current === modelData.id)
                        }
                    }
                }
            }

            Heading { text: qsTr("Window background opacity") }
            Label {
                Layout.fillWidth: true
                text: qsTr("100% is solid. Lower values show more of the background.")
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Slider {
                    objectName: "translucencySlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    value: Math.round(MaterialTheme.opacityFor(MaterialTheme.current) * 100)
                    onMoved: MaterialTheme.translucency = (100 - value) / 100
                    Accessible.name: qsTr("Window background opacity")
                }
                Label {
                    text: qsTr("%1% opaque").arg(Math.round(MaterialTheme.opacityFor(MaterialTheme.current) * 100))
                    color: root.colors.text
                }
                GlassButton {
                    text: qsTr("Use material default")
                    enabled: MaterialTheme.translucency >= 0
                    onClicked: MaterialTheme.translucency = -1
                }
            }

            Heading { text: qsTr("Theme tint") }

            RowLayout {
                Layout.fillWidth: true
                GlassButton {
                    text: qsTr("Choose tint color")
                    accent: MaterialTheme.tintColor
                    onClicked: {
                        colorPicker.targetKey = ""
                        colorPicker.selectedColor = MaterialTheme.tintColor
                        colorPicker.open()
                    }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    stepSize: .01
                    value: MaterialTheme.tintStrength
                    onMoved: MaterialTheme.tintStrength = value
                    Accessible.name: qsTr("Tint strength")
                }
                Label { text: qsTr("%1%").arg(Math.round(MaterialTheme.tintStrength * 100)); color: root.colors.text }
            }

            Heading { text: qsTr("Accent override") }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                GlassButton {
                    text: qsTr("Choose accent color…")
                    accent: MaterialTheme.forcedAccent || root.colors.accent
                    onClicked: {
                        colorPicker.targetKey = "forcedAccent"
                        colorPicker.selectedColor = MaterialTheme.forcedAccent || root.colors.accent
                        colorPicker.open()
                    }
                }
                GlassButton {
                    text: qsTr("Use material accents")
                    enabled: Boolean(MaterialTheme.forcedAccent)
                    onClicked: MaterialTheme.forcedAccent = ""
                }
            }

            Label {
                visible: MaterialTheme.colorTheme !== null
                text: MaterialTheme.colorTheme ? qsTr("Current theme: %1").arg(MaterialTheme.colorTheme.name) : ""
                color: root.colors.text
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                GlassButton { text: qsTr("Import material…"); enabled: !root.busy; onClicked: { root.fileAction = "material"; inputFile.open() } }
                GlassButton { text: qsTr("Export material…"); enabled: !root.busy; onClicked: root.save("material") }
                GlassButton { text: qsTr("Import theme…"); enabled: !root.busy; onClicked: { root.fileAction = "theme"; inputFile.open() } }
                GlassButton { text: qsTr("Export theme…"); enabled: !root.busy; onClicked: root.save("theme") }
                GlassButton { text: qsTr("Use material colors"); enabled: Boolean(MaterialTheme.colorTheme); onClicked: MaterialTheme.colorTheme = null }
            }
        }
    }

    Repeater {
        model: [
            {key: "main", title: qsTr("Download manager")},
            {key: "details", title: qsTr("Settings and download windows")}
        ]
        delegate: TabPage {
            id: backgroundCard
            required property int index
            required property var modelData
            pageRow: index
            visible: root.activeTab === 1
            readonly property var selected: WindowAppearance.background(modelData.key)

            ColumnLayout {
                width: parent.width
                spacing: 10
                Heading { text: backgroundCard.modelData.title }
                Choice {
                    selection: backgroundCard.selected.mode
                    model: [{label: qsTr("See-through desktop"), value: "desktop"}, {label: qsTr("Custom color"), value: "solid"},
                        {label: qsTr("Personal image or video"), value: "wallpaper"}]
                    onActivated: WindowAppearance.set(backgroundCard.modelData.key + "Mode", currentValue)
                    Accessible.name: backgroundCard.modelData.title
                }
                GlassButton {
                    visible: backgroundCard.selected.mode === "solid"
                    text: qsTr("Choose background color…")
                    onClicked: {
                        colorPicker.targetKey = backgroundCard.modelData.key + "Color"
                        colorPicker.selectedColor = backgroundCard.selected.color || root.colors.background
                        colorPicker.open()
                    }
                }
                GlassButton {
                    visible: backgroundCard.selected.mode === "wallpaper"
                    text: qsTr("Choose an image or video…")
                    onClicked: {
                        wallpaperPicker.targetKey = backgroundCard.modelData.key + "Media"
                        wallpaperPicker.open()
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: backgroundCard.selected.mode === "wallpaper" && Boolean(backgroundCard.selected.media)
                    text: visible ? engine.localPath(backgroundCard.selected.media) : ""
                    elide: Text.ElideMiddle
                    color: root.colors.muted
                }
            }
        }
    }

    TabPage {
        visible: root.activeTab === 2

        ColumnLayout {
            width: parent.width
            spacing: 10
            Heading { text: qsTr("Progress") }
            GridLayout {
                Layout.fillWidth: true
                columns: !root.sideTabs || width >= 320 ? 2 : 1
                IndicatorChoice {
                    label: qsTr("Progress shape")
                    model: root.shapeChoices
                    selection: WindowAppearance.progressShape
                    onChosen: value => WindowAppearance.set("progressShape", value)
                }
                IndicatorColorChoice {
                    label: qsTr("Progress colors")
                    indicatorRole: "progress"
                    selection: MaterialTheme.progressPalette
                    onChosen: value => MaterialTheme.progressPalette = value
                }
                IndicatorChoice {
                    label: qsTr("Progress animation")
                    model: WindowAppearance.animationChoices
                    selection: WindowAppearance.progressAnimation
                    onChosen: value => WindowAppearance.set("progressAnimation", value)
                }
                IndicatorChoice {
                    label: qsTr("Progress lighting")
                    model: WindowAppearance.lightingChoices
                    selection: WindowAppearance.progressLighting
                    onChosen: value => WindowAppearance.set("progressLighting", value)
                }
            }
            GlassProgress {
                Layout.preferredWidth: parent.width * .53
                Layout.preferredHeight: 38
                value: .64
                shape: WindowAppearance.progressShape === "material" ?
                    (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.progressShape
                animationStyle: WindowAppearance.progressAnimation
                startColor: MaterialTheme.progressColors[0]
                endColor: MaterialTheme.progressColors[1]
                showLabel: true
                animated: visible && root.previewActive
            }
            Heading { text: qsTr("Connections") }
            GridLayout {
                Layout.fillWidth: true
                columns: !root.sideTabs || width >= 320 ? 2 : 1
                IndicatorChoice {
                    label: qsTr("Connection shape")
                    model: root.shapeChoices
                    selection: WindowAppearance.connectionShape
                    onChosen: value => WindowAppearance.set("connectionShape", value)
                }
                IndicatorColorChoice {
                    label: qsTr("Connection colors")
                    indicatorRole: "connections"
                    selection: MaterialTheme.connectionPalette
                    onChosen: value => MaterialTheme.connectionPalette = value
                }
                IndicatorChoice {
                    label: qsTr("Connection animation")
                    model: WindowAppearance.animationChoices
                    selection: WindowAppearance.connectionAnimation
                    onChosen: value => WindowAppearance.set("connectionAnimation", value)
                }
                IndicatorChoice {
                    label: qsTr("Connection lighting")
                    model: WindowAppearance.lightingChoices
                    selection: WindowAppearance.connectionLighting
                    onChosen: value => WindowAppearance.set("connectionLighting", value)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [.32, .68, .80, .49, .98, .82]
                    delegate: ConnectionWater {
                        required property real modelData
                        Layout.fillWidth: true
                        value: modelData
                        receiving: visible && root.previewActive
                        phase: root.previewPhase
                        shape: WindowAppearance.connectionShape === "material" ?
                            (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.connectionShape
                        animationStyle: WindowAppearance.connectionAnimation
                        startColor: MaterialTheme.connectionColors[0]
                        endColor: MaterialTheme.connectionColors[1]
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("The pipes in the download window follow your progress and connection colors, lighting, and animation.")
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }
            Heading { text: qsTr("Transfer speed graph") }
            GridLayout {
                Layout.fillWidth: true
                columns: !root.sideTabs || width >= 320 ? 2 : 1
                IndicatorChoice {
                    label: qsTr("Graph style")
                    model: [{label: qsTr("Area"), value: "area"}, {label: qsTr("Line"), value: "line"}, {label: qsTr("Bars"), value: "bars"}]
                    selection: WindowAppearance.graphShape
                    onChosen: value => WindowAppearance.set("graphShape", value)
                }
                IndicatorChoice {
                    label: qsTr("Graph animation")
                    model: WindowAppearance.animationChoices
                    selection: WindowAppearance.graphAnimation
                    onChosen: value => WindowAppearance.set("graphAnimation", value)
                }
                IndicatorColorChoice {
                    label: qsTr("Graph colors")
                    indicatorRole: "graph"
                    selection: MaterialTheme.graphPalette
                    onChosen: value => MaterialTheme.graphPalette = value
                }
                IndicatorChoice {
                    label: qsTr("Graph lighting")
                    model: WindowAppearance.lightingChoices
                    selection: WindowAppearance.graphLighting
                    onChosen: value => WindowAppearance.set("graphLighting", value)
                }
            }
            TransferGraph {
                Layout.fillWidth: true
                Layout.preferredHeight: 68
                samples: [2, 3, 6, 6, 4, 8, 12, 9, 13, 12, 14, 13, 11, 14, 17, 16]
                graphShape: WindowAppearance.graphShape
                animationStyle: WindowAppearance.graphAnimation
                flowActive: visible && root.previewActive
                lineColor: MaterialTheme.graphColors[0]
                endpointColor: MaterialTheme.graphColors[1]
                gridColor: root.colors.divider
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.column: 0
        Layout.columnSpan: 2
        Layout.row: 3
        Switch {
            text: qsTr("Reduce animations")
            checked: MaterialTheme.reducedMotion
            onToggled: MaterialTheme.reducedMotion = checked
        }
        Item { Layout.fillWidth: true }
        GlassButton {
            text: qsTr("Reset appearance…")
            onClicked: resetDialog.open()
        }
    }

    Label {
        visible: Boolean(root.status)
        Layout.fillWidth: true
        Layout.column: 0
        Layout.columnSpan: 2
        Layout.row: 4
        text: root.status
        color: root.failed ? root.colors.destructive : root.colors.positive
        wrapMode: Text.WordWrap
    }

    DetachedConfirmation {
        id: resetDialog
        hostWindow: root.Window.window
        title: qsTr("Reset appearance?")
        message: qsTr("Restore the default material, tint, indicator styles, and backgrounds. Imported materials remain available.")
        confirmText: qsTr("Reset appearance")
        onConfirmed: {
            const imported = MaterialTheme.userMaterials
            WindowAppearance.applyBackup({}, true)
            MaterialTheme.userMaterials = imported
        }
    }

    ColorDialog {
        id: colorPicker
        property string targetKey
        onAccepted: {
            if (targetKey === "forcedAccent") MaterialTheme.forcedAccent = WindowAppearance.colorText(selectedColor)
            else if (targetKey) WindowAppearance.set(targetKey, WindowAppearance.colorText(selectedColor))
            else MaterialTheme.tintColor = selectedColor
        }
    }

    FileDialog {
        id: wallpaperPicker
        property string targetKey
        title: qsTr("Choose a background")
        nameFilters: [qsTr("Images and videos (*.png *.jpg *.jpeg *.webp *.bmp *.mp4 *.webm *.mov *.m4v)")]
        onAccepted: WindowAppearance.set(targetKey, String(selectedFile))
    }

    FileDialog {
        id: inputFile
        title: qsTr("Import Auralis appearance")
        nameFilters: [qsTr("Auralis JSON files (*.json)")]
        onAccepted: root.importFile(selectedFile)
    }

    FileDialog {
        id: outputFile
        title: qsTr("Export Auralis appearance")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [qsTr("Auralis JSON files (*.json)")]
        onAccepted: {
            const data = root.fileAction === "material" ? MaterialTheme.exportMaterial(MaterialTheme.current) : WindowAppearance.exportTheme()
            if (!data) { root.report(qsTr("Could not export the current appearance."), true); return }
            root.busy = true
            engine.request({local: "writeShareFile", file: selectedFile, data: data}, function(result, error) {
                root.busy = false
                root.report(error || (result ? qsTr("Appearance exported to %1").arg(result.path) : qsTr("Could not save the file.")),
                    Boolean(error || !result))
            })
        }
    }
}
