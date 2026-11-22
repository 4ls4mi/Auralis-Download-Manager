pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var backdrop
    readonly property var colors: MaterialTheme.palette
    property string fileAction
    property string status
    property bool failed: false
    property bool busy: false
    readonly property var shapeChoices: [
        {label: qsTr("Material default"), value: "material"}, {label: qsTr("Rounded"), value: "round"},
        {label: qsTr("Square"), value: "square"}, {label: qsTr("Bubble"), value: "bubble"},
        {label: qsTr("Faceted"), value: "prism"}, {label: qsTr("Ice"), value: "ice"}
    ]
    readonly property var fillChoices: [
        {label: qsTr("Sculpted Liquid Glass"), value: "sculpted"}, {label: qsTr("Default"), value: "default"}
    ]

    spacing: 13

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
        background: GlassSurface { role: "content"; backdropAvailable: root.backdrop.acrylic }
    }

    component Heading: Label {
        Layout.fillWidth: true
        color: root.colors.text
        font.pixelSize: 17
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    component Choice: ComboBox {
        Layout.fillWidth: true
        textRole: "label"
        valueRole: "value"
        currentIndex: indexOfValue(selection)
        required property string selection
    }

    TabBar {
        id: tabs
        Layout.fillWidth: true
        TabButton { text: qsTr("Materials and color") }
        TabButton { text: qsTr("Window backgrounds") }
        TabButton { text: qsTr("Indicators") }
    }

    Tile {
        visible: tabs.currentIndex === 0

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
                        text: modelData.name
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

            Heading { text: qsTr("Translucency") }

            RowLayout {
                Layout.fillWidth: true
                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    value: MaterialTheme.translucency >= 0 ? MaterialTheme.translucency * 100 :
                        (1 - MaterialTheme.opacityFor(MaterialTheme.current)) * 100
                    onMoved: MaterialTheme.translucency = value / 100
                    Accessible.name: qsTr("Translucency")
                }
                Label {
                    text: qsTr("%1%").arg(Math.round(MaterialTheme.translucency >= 0 ?
                        MaterialTheme.translucency * 100 : (1 - MaterialTheme.opacityFor(MaterialTheme.current)) * 100))
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
        delegate: Tile {
            id: backgroundCard
            required property var modelData
            visible: tabs.currentIndex === 1
            readonly property var selected: WindowAppearance.background(modelData.key)

            ColumnLayout {
                width: parent.width
                spacing: 10
                Heading { text: backgroundCard.modelData.title }
                Choice {
                    selection: backgroundCard.selected.mode
                    model: [{label: qsTr("See-through desktop"), value: "desktop"}, {label: qsTr("Solid color"), value: "solid"},
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

    Tile {
        visible: tabs.currentIndex === 2

        ColumnLayout {
            width: parent.width
            spacing: 10
            Heading { text: qsTr("Progress") }
            RowLayout {
                Layout.fillWidth: true
                Choice {
                    model: root.shapeChoices
                    selection: WindowAppearance.progressShape
                    onActivated: WindowAppearance.set("progressShape", currentValue)
                    Accessible.name: qsTr("Progress shape")
                }
                Choice {
                    model: root.fillChoices
                    selection: WindowAppearance.progressFill
                    onActivated: WindowAppearance.set("progressFill", currentValue)
                    Accessible.name: qsTr("Progress fill")
                }
            }
            GlassProgress {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                value: .64
                shape: WindowAppearance.progressShape === "material" ?
                    (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.progressShape
                fillStyle: WindowAppearance.progressFill
                showLabel: true
                animated: visible
            }
            Heading { text: qsTr("Connections") }
            RowLayout {
                Layout.fillWidth: true
                Choice {
                    model: root.shapeChoices
                    selection: WindowAppearance.connectionShape
                    onActivated: WindowAppearance.set("connectionShape", currentValue)
                    Accessible.name: qsTr("Connection shape")
                }
                Choice {
                    model: root.fillChoices
                    selection: WindowAppearance.connectionFill
                    onActivated: WindowAppearance.set("connectionFill", currentValue)
                    Accessible.name: qsTr("Connection fill")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [.32, .68, .80, .49, .98, .82]
                    delegate: GlassProgress {
                        required property real modelData
                        Layout.fillWidth: true
                        value: modelData
                        shape: WindowAppearance.connectionShape === "material" ?
                            (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.connectionShape
                        fillStyle: WindowAppearance.connectionFill
                        showLabel: false
                        animated: visible
                    }
                }
            }
            Heading { text: qsTr("Transfer speed graph") }
            Choice {
                model: [{label: qsTr("Area"), value: "area"}, {label: qsTr("Line"), value: "line"}, {label: qsTr("Bars"), value: "bars"}]
                selection: WindowAppearance.graphShape
                onActivated: WindowAppearance.set("graphShape", currentValue)
                Accessible.name: qsTr("Graph style")
            }
            TransferGraph {
                Layout.fillWidth: true
                Layout.preferredHeight: 68
                samples: [2, 3, 6, 6, 4, 8, 12, 9, 13, 12, 14, 13, 11, 14, 17, 16]
                lineColor: root.colors.accent
                endpointColor: root.colors.secondary
                gridColor: root.colors.divider
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
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
        text: root.status
        color: root.failed ? root.colors.destructive : root.colors.positive
        wrapMode: Text.WordWrap
    }

    Dialog {
        id: resetDialog
        anchors.centerIn: parent
        modal: true
        title: qsTr("Reset appearance?")
        standardButtons: Dialog.Reset | Dialog.Cancel
        Label {
            text: qsTr("Restore the default material, tint, indicator styles, and backgrounds. Imported materials remain available.")
            color: root.colors.text
            wrapMode: Text.WordWrap
            width: 350
        }
        onReset: {
            const imported = MaterialTheme.userMaterials
            WindowAppearance.applyBackup({}, true)
            MaterialTheme.userMaterials = imported
            close()
        }
    }

    ColorDialog {
        id: colorPicker
        property string targetKey
        onAccepted: {
            if (targetKey) WindowAppearance.set(targetKey, WindowAppearance.colorText(selectedColor))
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
