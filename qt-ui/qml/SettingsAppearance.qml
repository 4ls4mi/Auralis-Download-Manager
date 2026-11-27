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

    function editMaterialColor(button, role, value) {
        const material = MaterialTheme.current
        editColor(value, color => {
            if (button)
                WindowAppearance.setButtonPaletteColor(material, role, color)
            else
                WindowAppearance.setMaterialColor(material, role, color)
        })
    }

    function editColor(value, apply) {
        materialColorPicker.applyColor = apply
        materialColorPicker.selectedColor = value
        materialColorPicker.hue = Math.max(0, materialColorPicker.selectedColor.hsvHue)
        materialColorPicker.saturation = materialColorPicker.selectedColor.hsvSaturation
        materialColorPicker.brightness = materialColorPicker.selectedColor.hsvValue
        materialColorPicker.open()
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
                if (id) {
                    if (Object.prototype.hasOwnProperty.call(response, "qtCustomization"))
                        WindowAppearance.setMaterialCustomization(id, response.qtCustomization)
                    MaterialTheme.current = id
                }
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

    component PercentSlider: RowLayout {
        id: field

        required property string label
        required property int percentage
        signal changedByUser(int percentage)

        Layout.fillWidth: true

        Label {
            text: field.label
            color: root.colors.text
            wrapMode: Text.WordWrap
            Layout.maximumWidth: TypographyScale.pixels(160)
        }

        GlassSlider {
            id: slider
            Layout.fillWidth: true
            from: 60
            to: 160
            stepSize: 1
            value: field.percentage
            Accessible.name: field.label
            onMoved: field.changedByUser(Math.round(value))
        }

        NumeralLabel {
            valueText: qsTr("%1%").arg(Math.round(slider.value))
            color: root.colors.muted
        }
    }

    component MaterialColorField: ColumnLayout {
        id: field

        required property var option
        property bool buttonColor: false
        readonly property string chosenColor: buttonColor
            ? WindowAppearance.buttonPaletteColor(MaterialTheme.current, option.role)
            : WindowAppearance.materialColor(MaterialTheme.current, option.role)
        readonly property color fallbackColor: {
            switch (option.role) {
            case "header": return root.colors.roleFaces?.title || root.colors.background
            case "footer": return root.colors.roleFaces?.footer || root.colors.background
            case "sidebar": return root.colors.roleFaces?.sidebar || root.colors.background
            case "content": return root.colors.roleFaces?.content || root.colors.background
            case "menu": return MaterialTheme.menuColors.surface
            default: return root.colors[option.role]
            }
        }
        readonly property color effectiveColor: buttonColor
            ? MaterialTheme.buttonTint(MaterialTheme.current, fallbackColor, option.role)
            : chosenColor || fallbackColor

        Layout.fillWidth: true
        Layout.minimumWidth: 1
        Layout.preferredWidth: 230
        spacing: 4

        function choose(value) {
            if (buttonColor)
                WindowAppearance.setButtonPaletteColor(MaterialTheme.current, option.role, value)
            else
                WindowAppearance.setMaterialColor(MaterialTheme.current, option.role, value)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 4
                color: field.effectiveColor
                border.color: MaterialTheme.controlIconInk(root.colors.divider, color)
            }
            Label {
                Layout.fillWidth: true
                text: field.option.label
                color: root.colors.text
                wrapMode: Text.WordWrap
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: field.option.suggestions
                delegate: Button {
                    id: swatch
                    required property string modelData
                    required property int index
                    padding: 0
                    implicitWidth: 28
                    implicitHeight: 28
                    hoverEnabled: true
                    Accessible.name: qsTr("Suggested color %1 for %2").arg(index + 1).arg(field.option.label)
                    Accessible.selected: modelData === field.chosenColor
                    onClicked: field.choose(modelData)

                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        color: swatch.modelData
                        radius: 5
                        border.width: swatch.visualFocus || swatch.modelData === field.chosenColor ? 2 : 1
                        border.color: MaterialTheme.controlIconInk(root.colors.divider, color)
                    }
                }
            }

            GlassButton {
                text: qsTr("Pick…")
                Accessible.name: qsTr("Pick a custom color for %1").arg(field.option.label)
                onClicked: root.editMaterialColor(field.buttonColor, field.option.role, field.effectiveColor)
            }

            GlassButton {
                text: qsTr("Default")
                enabled: Boolean(field.chosenColor)
                Accessible.name: qsTr("Reset %1 to the material default").arg(field.option.label)
                onClicked: field.choose("")
            }
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
        id: materialsPage
        visible: root.activeTab === 0

        ColumnLayout {
            width: materialsPage.availableWidth
            spacing: 12
            Heading { text: qsTr("Appearance preset") }

            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: Math.max(1, Math.min(4, Math.floor(parent.width / 160)))
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

            Heading {
                visible: MaterialTheme.mdmAppearance
                text: qsTr("Theme mode")
            }
            Choice {
                visible: MaterialTheme.mdmAppearance
                selection: MaterialTheme.mdmMode
                model: [
                    {label: qsTr("Follow system"), value: "system"},
                    {label: qsTr("Light"), value: "light"},
                    {label: qsTr("Dark"), value: "dark"}
                ]
                Accessible.name: qsTr("Theme mode")
                onActivated: MaterialTheme.mdmMode = currentValue
            }

            IndicatorChoice {
                objectName: "fracturedPanelFinish"
                visible: root.colors.layout === "fracturedPearl"
                label: qsTr("Panel finish")
                model: MaterialTheme.fracturedFinishChoices
                selection: MaterialTheme.fracturedFinish
                onChosen: value => MaterialTheme.fracturedFinish = value
            }

            Heading { text: qsTr("Layer and text colors") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("These colors apply only to the selected preset. Auralis adjusts text for contrast where needed.")
                color: root.colors.muted
            }
            GridLayout {
                Layout.fillWidth: true
                columns: parent.width >= 480 ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: [
                        {role: "header", label: qsTr("Header"),
                            suggestions: ["#272341", "#214659", "#5a3245"]},
                        {role: "footer", label: qsTr("Footer"),
                            suggestions: ["#2e2944", "#233f4c", "#57374a"]},
                        {role: "sidebar", label: qsTr("Sidebar"),
                            suggestions: ["#322762", "#19465a", "#643b4e"]},
                        {role: "content", label: qsTr("Content"),
                            suggestions: ["#202634", "#293947", "#f1edf8"]},
                        {role: "menu", label: qsTr("Menus"),
                            suggestions: ["#342944", "#194050", "#f5ecf0"]},
                        {role: "text", label: qsTr("Interface text"),
                            suggestions: ["#f5f5f8", "#cbdbf1", "#172033"]}
                    ]
                    delegate: MaterialColorField {
                        required property var modelData
                        option: modelData
                    }
                }
            }
            GlassButton {
                text: qsTr("Reset layer and text colors")
                enabled: WindowAppearance.materialColorRoles.some(role => Boolean(WindowAppearance.materialColor(MaterialTheme.current, role)))
                onClicked: WindowAppearance.resetMaterialColors(MaterialTheme.current)
            }

            Heading { text: qsTr("Button colors") }
            IndicatorChoice {
                label: qsTr("Button palette")
                model: [
                    {label: qsTr("Material default"), value: "material"},
                    {label: qsTr("Cool"), value: "cool"},
                    {label: qsTr("Warm"), value: "warm"},
                    {label: qsTr("Custom"), value: "custom"}
                ]
                selection: WindowAppearance.buttonPalette(MaterialTheme.current)
                onChosen: value => WindowAppearance.setButtonPalette(MaterialTheme.current, value)
            }
            GridLayout {
                visible: WindowAppearance.buttonPalette(MaterialTheme.current) === "custom"
                Layout.fillWidth: true
                columns: parent.width >= 480 ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: [
                        {role: "accent", label: qsTr("Primary buttons"),
                            suggestions: ["#7654cf", "#286ab7", "#c14978"]},
                        {role: "secondary", label: qsTr("Secondary buttons"),
                            suggestions: ["#586e8f", "#368392", "#925da0"]},
                        {role: "positive", label: qsTr("Confirm buttons"),
                            suggestions: ["#28795b", "#298582", "#46763d"]},
                        {role: "caution", label: qsTr("Caution buttons"),
                            suggestions: ["#986d23", "#b26c4a", "#ae8725"]},
                        {role: "destructive", label: qsTr("Destructive buttons"),
                            suggestions: ["#a84858", "#ad4474", "#b55139"]}
                    ]
                    delegate: MaterialColorField {
                        required property var modelData
                        option: modelData
                        buttonColor: true
                    }
                }
            }
            GlassButton {
                text: qsTr("Reset button colors")
                enabled: WindowAppearance.buttonPalette(MaterialTheme.current) !== "material"
                    || WindowAppearance.buttonColorRoles.some(role => Boolean(WindowAppearance.buttonPaletteColor(MaterialTheme.current, role)))
                onClicked: WindowAppearance.resetButtonPalette(MaterialTheme.current)
            }

            Heading { visible: !MaterialTheme.mdmAppearance; text: qsTr("Window background opacity") }
            NumeralLabel {
                Layout.fillWidth: true
                visible: !MaterialTheme.mdmAppearance
                valueText: qsTr("100% is solid. Lower values show more of the background.")
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }

            RowLayout {
                visible: !MaterialTheme.mdmAppearance
                Layout.fillWidth: true
                    GlassSlider {
                    objectName: "translucencySlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    value: Math.round(MaterialTheme.opacityFor(MaterialTheme.current) * 100)
                    onMoved: MaterialTheme.translucency = (100 - value) / 100
                    Accessible.name: qsTr("Window background opacity")
                }
                NumeralLabel {
                    valueText: qsTr("%1% opaque").arg(Math.round(MaterialTheme.opacityFor(MaterialTheme.current) * 100))
                    color: root.colors.text
                }
                GlassButton {
                    text: qsTr("Use material default")
                    enabled: MaterialTheme.translucency >= 0
                    onClicked: MaterialTheme.translucency = -1
                }
            }

            Heading { visible: !MaterialTheme.mdmAppearance; text: qsTr("Theme tint") }

            RowLayout {
                visible: !MaterialTheme.mdmAppearance
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
                    GlassSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    stepSize: .01
                    value: MaterialTheme.tintStrength
                    onMoved: MaterialTheme.tintStrength = value
                    Accessible.name: qsTr("Tint strength")
                }
                NumeralLabel { valueText: qsTr("%1%").arg(Math.round(MaterialTheme.tintStrength * 100)); color: root.colors.text }
            }

            Heading { visible: !MaterialTheme.mdmAppearance; text: qsTr("Accent override") }

            Flow {
                visible: !MaterialTheme.mdmAppearance
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
                visible: !MaterialTheme.mdmAppearance && MaterialTheme.colorTheme !== null
                text: MaterialTheme.colorTheme ? qsTr("Current theme: %1").arg(MaterialTheme.colorTheme.name) : ""
                color: root.colors.text
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                GlassButton { text: qsTr("Import material…"); enabled: !root.busy; onClicked: { root.fileAction = "material"; inputFile.open() } }
                GlassButton { text: qsTr("Export material…"); enabled: !root.busy && !MaterialTheme.mdmAppearance; onClicked: root.save("material") }
                GlassButton { text: qsTr("Import theme…"); enabled: !root.busy; onClicked: { root.fileAction = "theme"; inputFile.open() } }
                GlassButton { text: qsTr("Export theme…"); enabled: !root.busy; onClicked: root.save("theme") }
                GlassButton { text: qsTr("Use material colors"); visible: !MaterialTheme.mdmAppearance; enabled: Boolean(MaterialTheme.colorTheme); onClicked: MaterialTheme.colorTheme = null }
            }
        }
    }

    TabPage {
        visible: root.activeTab === 1
        ColumnLayout {
            width: parent.width
            spacing: 10
            Heading { text: qsTr("Window corners") }
            Choice {
                enabled: !MaterialTheme.mdmAppearance
                selection: WindowAppearance.cornerPlacement
                model: [
                    {label: qsTr("Square"), value: "square"},
                    {label: qsTr("Round top corners"), value: "top"},
                    {label: qsTr("Round bottom corners"), value: "bottom"},
                    {label: qsTr("Round all corners"), value: "all"}
                ]
                Accessible.name: qsTr("Which corners to round")
                onActivated: WindowAppearance.set("cornerPlacement", currentValue)
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Radius"); color: root.colors.text }
                GlassSlider {
                    Layout.fillWidth: true
                    enabled: !MaterialTheme.mdmAppearance && WindowAppearance.cornerPlacement !== "square"
                    from: 0
                    to: 40
                    stepSize: 1
                    live: false
                    value: WindowAppearance.cornerRadius
                    Accessible.name: qsTr("Window corner radius")
                    onValueChanged: {
                        if (value !== WindowAppearance.cornerRadius)
                            WindowAppearance.set("cornerRadius", Math.round(value))
                    }
                }
                Label {
                    text: qsTr("%1 px").arg(WindowAppearance.cornerRadius)
                    color: root.colors.muted
                }
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
            pageRow: index + 1
            visible: root.activeTab === 1 && !MaterialTheme.mdmAppearance
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
        id: indicatorsPage
        visible: root.activeTab === 2

        readonly property bool customFill: !MaterialTheme.mdmAppearance || WindowAppearance.customProgressFill
        readonly property color materialTrack: !customFill && root.colors.mdm
            ? root.colors.mdm.progressTrack : root.colors.background

        ColumnLayout {
            width: parent.width
            spacing: 10
            Label {
                visible: MaterialTheme.mdmAppearance
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.colors.muted
                text: qsTr("Classic materials supply the default connection and speed graph styles.")
            }
            Heading { text: qsTr("Progress fill") }
            GlassSwitch {
                objectName: "customProgressFill"
                visible: MaterialTheme.mdmAppearance
                text: qsTr("Use custom progress fill")
                checked: WindowAppearance.customProgressFill
                onToggled: WindowAppearance.set("customProgressFill", checked)
            }
            GridLayout {
                Layout.fillWidth: true
                columns: parent.width >= 320 ? 2 : 1
                IndicatorChoice {
                    enabled: indicatorsPage.customFill
                    label: qsTr("Fill layout")
                    model: WindowAppearance.progressLayoutChoices
                    selection: WindowAppearance.progressLayout
                    onChosen: value => WindowAppearance.set("progressLayout", value)
                }
                IndicatorChoice {
                    label: qsTr("Progress shape")
                    model: root.shapeChoices
                    selection: WindowAppearance.progressShape
                    onChosen: value => WindowAppearance.set("progressShape", value)
                }
                IndicatorColorChoice {
                    enabled: indicatorsPage.customFill
                    label: qsTr("Fill colors")
                    indicatorRole: "progress"
                    selection: MaterialTheme.progressPalette
                    onChosen: value => MaterialTheme.progressPalette = value
                }
                IndicatorChoice {
                    enabled: indicatorsPage.customFill
                    label: qsTr("Layout animation")
                    model: WindowAppearance.progressAnimationChoices
                    selection: WindowAppearance.progressAnimation
                    onChosen: value => WindowAppearance.set("progressAnimation", value)
                }
                IndicatorChoice {
                    enabled: indicatorsPage.customFill
                    label: qsTr("Fill theme")
                    model: WindowAppearance.lightingChoices
                    selection: WindowAppearance.progressLighting
                    onChosen: value => WindowAppearance.set("progressLighting", value)
                }
            }
            PercentSlider {
                label: qsTr("Progress bar thickness")
                percentage: WindowAppearance.progressThickness
                onChangedByUser: value => WindowAppearance.set("progressThickness", value)
            }
            GlassProgress {
                objectName: "progressFillPreview"
                Layout.preferredWidth: parent.width * .64
                baseHeight: 38
                value: .64
                animationStyle: WindowAppearance.progressAnimation
                startColor: MaterialTheme.progressColors[0]
                endColor: MaterialTheme.progressColors[1]
                showLabel: true
                animated: visible && root.previewActive
            }

            Heading { text: qsTr("Progress track") }
            Label {
                Layout.fillWidth: true
                color: root.colors.muted
                text: qsTr("Appearance of the unfilled part of the bar.")
                wrapMode: Text.WordWrap
            }
            GridLayout {
                Layout.fillWidth: true
                columns: parent.width >= 320 ? 2 : 1

                IndicatorChoice {
                    label: qsTr("Track finish")
                    model: WindowAppearance.progressTrackFinishChoices
                    selection: WindowAppearance.progressTrackFinish
                    onChosen: value => WindowAppearance.set("progressTrackFinish", value)
                }
                IndicatorChoice {
                    label: qsTr("Track color")
                    model: WindowAppearance.colorValid(selection)
                        ? WindowAppearance.progressTrackColorChoices.concat([{label: qsTr("Custom color"), value: selection}])
                        : WindowAppearance.progressTrackColorChoices
                    selection: WindowAppearance.progressTrackColor
                    colorOptionPreview: value => {
                        const colors = WindowAppearance.trackColors(value)
                        return colors.length ? colors : [indicatorsPage.materialTrack, indicatorsPage.materialTrack]
                    }
                    onChosen: value => WindowAppearance.set("progressTrackColor", value)
                }
            }
            GlassButton {
                objectName: "chooseProgressTrackColor"
                text: qsTr("Pick a track color…")
                onClicked: root.editColor(WindowAppearance.progressTrackColors[0] || indicatorsPage.materialTrack,
                    color => WindowAppearance.set("progressTrackColor", color))
            }
            GlassProgress {
                objectName: "progressTrackPreview"
                Layout.preferredWidth: parent.width * .64
                baseHeight: 38
                value: 0
                showLabel: true
                startColor: MaterialTheme.progressColors[0]
                endColor: MaterialTheme.progressColors[1]
            }
            Heading { text: qsTr("Connections") }
            GridLayout {
                visible: !MaterialTheme.mdmAppearance
                Layout.fillWidth: true
                columns: !root.sideTabs || parent.width >= 320 ? 2 : 1
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
            PercentSlider {
                label: qsTr("Connection block size")
                percentage: WindowAppearance.connectionBlockSize
                onChangedByUser: value => WindowAppearance.set("connectionBlockSize", value)
            }
            MdmSegmentMap {
                visible: MaterialTheme.mdmAppearance
                Layout.fillWidth: true
                totalBytes: 100
                segments: [{start: 0, cursor: 25, end: 25}, {start: 25, cursor: 38, end: 50},
                    {start: 50, cursor: 76, end: 80}, {start: 80, cursor: 80, end: 100}]
            }
            RowLayout {
                visible: !MaterialTheme.mdmAppearance
                Layout.fillWidth: true
                Repeater {
                    model: [.32, .68, .80, .49, .98, .82]
                    delegate: ConnectionWater {
                        required property real modelData
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
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
                visible: !MaterialTheme.mdmAppearance
                text: qsTr("The pipes in the download window follow your progress and connection colors, lighting, and animation.")
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }
            Heading { text: qsTr("Transfer speed graph") }
            IndicatorChoice {
                Layout.fillWidth: true
                label: qsTr("Graph material")
                model: WindowAppearance.graphMaterialChoices
                selection: WindowAppearance.graphMaterial
                onChosen: value => WindowAppearance.set("graphMaterial", value)
            }
            GridLayout {
                visible: !MaterialTheme.mdmAppearance || WindowAppearance.graphMaterial !== "default"
                Layout.fillWidth: true
                columns: !root.sideTabs || parent.width >= 320 ? 2 : 1
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
        Layout.row: root.activeTab === 1 && !root.sideTabs ? 4 : 3
        GlassSwitch {
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
        Layout.row: root.activeTab === 1 && !root.sideTabs ? 5 : 4
        text: root.status
        color: root.failed ? root.colors.destructive : root.colors.positive
        wrapMode: Text.WordWrap
    }

    DetachedConfirmation {
        id: resetDialog
        sizePreferenceKey: "reset-appearance"
        hostWindow: root.Window.window
        title: qsTr("Reset appearance?")
        message: qsTr("Restore the default material, colors, indicator styles and sizes, and backgrounds. Imported materials remain available.")
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

    component ColorSlider: GlassSlider {
        id: control

        required property Gradient spectrum
        required property color sample

        Layout.fillWidth: true
        from: 0
        to: 1

        background: Rectangle {
            id: strip

            implicitWidth: 200
            implicitHeight: 16
            x: control.leftPadding + control.thumbExtent / 2
            y: control.topPadding + (control.availableHeight - height) / 2
            width: Math.max(0, control.availableWidth - control.thumbExtent)
            height: implicitHeight
            radius: height / 2
            gradient: control.spectrum
            transform: Scale {
                origin.x: strip.width / 2
                xScale: control.mirrored ? -1 : 1
            }
        }

        handle: Item {
            implicitWidth: control.thumbExtent
            implicitHeight: control.thumbExtent
            x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
            y: control.topPadding + (control.availableHeight - height) / 2

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#171823"
                border.width: control.visualFocus ? 2 : 0
                border.color: MaterialTheme.controlIconInk(root.colors.accent, root.colors.background)
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: width / 2
                color: control.sample
                border.width: 2
                border.color: "white"
            }
        }
    }

    Dialog {
        id: materialColorPicker
        objectName: "materialColorPicker"

        property var applyColor: null
        property real hue: 0
        property real saturation: 0
        property real brightness: 1
        property color selectedColor: "black"

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.max(0, Math.min(400, (parent ? parent.width : 432) - 32))
        title: qsTr("Choose a color")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        palette.window: root.colors.background
        palette.windowText: root.colors.text
        palette.text: root.colors.text
        palette.highlight: root.colors.accent

        onAccepted: {
            if (applyColor)
                applyColor(WindowAppearance.colorText(selectedColor))
        }

        function updatePreview() {
            selectedColor = Qt.hsva(hue === 1 ? 0 : hue, saturation, brightness, 1)
        }

        contentItem: ColumnLayout {
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 8
                color: materialColorPicker.selectedColor
                border.color: MaterialTheme.controlIconInk(root.colors.divider, color)
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("Selected color")
            }

            Label { text: qsTr("Hue"); color: root.colors.text }
            ColorSlider {
                objectName: "materialHueSlider"
                spectrum: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ff0000" }
                    GradientStop { position: 1 / 6; color: "#ffff00" }
                    GradientStop { position: 2 / 6; color: "#00ff00" }
                    GradientStop { position: 3 / 6; color: "#00ffff" }
                    GradientStop { position: 4 / 6; color: "#0000ff" }
                    GradientStop { position: 5 / 6; color: "#ff00ff" }
                    GradientStop { position: 1; color: "#ff0000" }
                }
                sample: Qt.hsva(value === 1 ? 0 : value, 1, 1, 1)
                stepSize: 1 / 360
                value: materialColorPicker.hue
                Accessible.name: qsTr("Hue")
                onMoved: {
                    materialColorPicker.hue = value
                    if (materialColorPicker.saturation < .01)
                        materialColorPicker.saturation = .7
                    if (materialColorPicker.brightness < .01)
                        materialColorPicker.brightness = .75
                    materialColorPicker.updatePreview()
                }
            }
            Label { text: qsTr("Saturation"); color: root.colors.text }
            ColorSlider {
                spectrum: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.hsva(0, 0, materialColorPicker.brightness, 1) }
                    GradientStop { position: 1; color: Qt.hsva(materialColorPicker.hue, 1, materialColorPicker.brightness, 1) }
                }
                sample: materialColorPicker.selectedColor
                stepSize: .01
                value: materialColorPicker.saturation
                Accessible.name: qsTr("Saturation")
                onMoved: {
                    materialColorPicker.saturation = value
                    materialColorPicker.updatePreview()
                }
            }
            Label { text: qsTr("Brightness"); color: root.colors.text }
            ColorSlider {
                spectrum: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "black" }
                    GradientStop { position: 1; color: Qt.hsva(materialColorPicker.hue, materialColorPicker.saturation, 1, 1) }
                }
                sample: materialColorPicker.selectedColor
                stepSize: .01
                value: materialColorPicker.brightness
                Accessible.name: qsTr("Brightness")
                onMoved: {
                    materialColorPicker.brightness = value
                    materialColorPicker.updatePreview()
                }
            }
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
            const material = MaterialTheme.current
            const data = root.fileAction === "material"
                ? Object.assign({}, MaterialTheme.exportMaterial(material), {qtCustomization: WindowAppearance.materialCustomization(material)})
                : WindowAppearance.exportTheme()
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
