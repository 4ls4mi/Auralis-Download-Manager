pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: root

    required property var field
    required property real editorWidth
    property bool busy: false
    property var cells: []
    property var regional: ({})
    property bool expanded: field.key === "category_dirs" || field.section === "File types"
    property string cookieBrowser: ""
    readonly property bool browserProfile: field.key === "video_cookies_profile"
    readonly property bool browserCapture: field.key === "browsers"
    readonly property bool sounds: field.key === "sounds"
    readonly property var soundEvents: [
        qsTr("Download complete"),
        qsTr("Download failed"),
        qsTr("Queue started"),
        qsTr("Queue stopped or finished")
    ]
    readonly property var colors: MaterialTheme.palette
    readonly property string kind: field.kind || "text"
    readonly property bool complex: kind === "table" || kind === "lines" || kind === "multiline" || kind === "regional"
    readonly property bool unavailable: field.key === "cnl_on" || field.key === "cnl_sites"
    readonly property var choices: (field.options || []).map((choice, index) =>
        typeof choice === "string" ? ({label: choice, value: index}) : choice)
    signal commit(var value, var options)

    enabled: !busy
    spacing: 8

    function loadDraft() {
        if (kind === "table" && !browserCapture) cells = (field.value || []).map(row => Array.from(row))
        else if (kind === "regional") regional = Object.assign({}, field.value)
    }

    function defaultCell(column) {
        if (column.options && column.options.length) return column.options[0].value
        if (column.kind === "boolean") return false
        if (column.kind === "number") return 1
        return ""
    }

    function changeSound(index, checked, path) {
        const rows = cells.slice()
        rows[index] = [checked, path]
        cells = rows
    }

    function choiceIndex(model, value, fallback = -1) {
        const index = model.findIndex(entry => entry.value === value || String(entry.value) === String(value))
        return index === -1 ? fallback : index
    }

    function saveLine(value) {
        if (kind === "number") {
            if (!String(value).trim()) return
            const number = Number(value)
            if (Number.isInteger(number) && number >= (field.minimum ?? 0) && number <= (field.maximum ?? 2147483647) &&
                number !== field.value) commit(number, {})
        } else if (kind === "password" ? Boolean(value) : value !== String(field.value ?? "")) {
            commit(value, {})
        }
    }

    Component.onCompleted: loadDraft()
    onFieldChanged: loadDraft()

    component FieldBox: TextField {
        color: root.colors.text
        placeholderTextColor: root.colors.muted
        selectByMouse: true
        background: GlassSurface { role: "field" }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Label {
                Layout.fillWidth: true
                text: root.field.label
                color: root.colors.text
                wrapMode: Text.WordWrap
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.unavailable ? qsTr("Click’n’Load is unavailable. Existing settings are preserved.") : (root.kind === "number" ? qsTr("Allowed range: %1–%2. %3").arg(root.field.minimum ?? 0).arg(root.field.maximum ?? 2147483647).arg(root.field.description || "") : root.field.description || "")
                color: root.colors.muted
                wrapMode: Text.WordWrap
                font.pixelSize: TypographyScale.pixels(12)
            }
        }

        Loader {
            visible: !root.browserCapture
            Layout.preferredWidth: root.kind === "boolean" ? 56 : root.editorWidth
            Layout.minimumWidth: root.kind === "boolean" ? 48 : 125
            active: !root.browserCapture && !root.unavailable && !root.browserProfile
            sourceComponent: root.complex ? expandButton : root.kind === "boolean" ? boolControl
                : root.kind === "select" ? selectControl : root.field.key === "video_cookies_file" ? cookieControl : root.kind === "number" ? numberControl : inputControl
        }
    }

    GridLayout {
        Layout.fillWidth: true
        visible: root.browserCapture
        columns: width >= TypographyScale.pixels(420) ? 2 : 1
        columnSpacing: 12
        rowSpacing: 2

        Repeater {
            model: root.browserCapture ? root.field.captureBrowsers || [] : []

            delegate: CheckBox {
                required property var modelData
                objectName: "browserCapture:" + modelData.name
                Layout.fillWidth: true
                text: modelData.name
                checked: modelData.enabled
                palette.windowText: root.colors.text
                palette.highlight: root.colors.accent
                Accessible.name: text
                onToggled: root.commit(checked, {browser: modelData.name})
            }
        }
    }

    Loader {
        Layout.fillWidth: true
        active: root.browserProfile
        sourceComponent: profileControl
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.colors.divider
    }

    Component {
        id: boolControl
        GlassSwitch {
            checked: Boolean(root.field.value)
            Accessible.name: root.field.label
            onToggled: root.commit(checked, {})
        }
    }

    Component {
        id: selectControl
        GlassComboBox {
            model: root.choices
            textRole: "label"
            valueRole: "value"
            currentIndex: root.choiceIndex(root.choices, root.field.value)
            displayText: currentIndex < 0 ? qsTr("Choose an option") : currentText
            Accessible.name: root.field.label
            palette.text: root.colors.text
            palette.buttonText: root.colors.text
            palette.base: root.colors.background
            onActivated: root.commit(currentValue, {})
        }
    }

    Component {
        id: numberControl
        SpinBox {
            from: root.field.minimum ?? 0
            to: root.field.maximum ?? 2147483647
            value: Number(root.field.value ?? from)
            editable: true
            Accessible.name: root.field.label
            onValueModified: root.commit(value, {})
        }
    }

    Component {
        id: inputControl
        RowLayout {
            spacing: 6
            FieldBox {
                id: editable
                Layout.fillWidth: true
                text: String(root.field.value ?? "")
                font.family: root.kind === "number" && text.length
                    ? root.Window.window?.numeralInputFamily?.() || "" : root.Window.window?.font.family || ""
                Accessible.name: root.field.label
                echoMode: root.kind === "password" ? TextInput.Password : TextInput.Normal
                placeholderText: root.kind === "password" && root.field.saved ? qsTr("Saved password") : ""
                inputMethodHints: root.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
                validator: root.kind === "number" ? numericValidator : null
                onEditingFinished: root.saveLine(text)

                IntValidator {
                    id: numericValidator
                    bottom: root.field.minimum ?? 0
                    top: root.field.maximum ?? 2147483647
                }
            }

            GlassButton {
                visible: root.kind === "password" && Boolean(root.field.saved)
                text: qsTr("Clear")
                Accessible.name: qsTr("Clear saved password")
                onClicked: root.commit("", {clear: true})
            }
        }
    }

    Component {
        id: cookieControl
        RowLayout {
            Label {
                Layout.fillWidth: true
                text: root.field.value || qsTr("No file selected")
                color: root.colors.muted
                elide: Text.ElideMiddle
                ToolTip.visible: cookieHover.hovered && Boolean(root.field.value)
                ToolTip.text: root.field.value ? String(root.field.value) : ""
                HoverHandler { id: cookieHover }
            }
            GlassButton { text: qsTr("Choose…"); onClicked: cookies.open() }
            GlassButton {
                visible: Boolean(root.field.value)
                text: qsTr("Clear")
                onClicked: root.commit("", {})
            }
            FileDialog {
                id: cookies
                title: qsTr("Choose a Netscape cookies file")
                nameFilters: [qsTr("Text files (*.txt)")]
                onAccepted: root.commit(engine.localPath(selectedFile), {})
            }
        }
    }

    Component {
        id: profileControl
        ColumnLayout {
            id: profileEditor
            property var foundProfiles: []
            property string problem: ""
            property string detectedBrowser: ""
            property bool finding: false

            function discover() {
                const browser = root.cookieBrowser
                finding = true
                problem = ""
                foundProfiles = []
                detectedBrowser = browser
                engine.request({local: "browserProfiles", browser: browser}, function(result, error) {
                    profileEditor.finding = false
                    if (root.cookieBrowser !== browser)
                        return
                    profileEditor.foundProfiles = result || []
                    profileEditor.problem = error || (!profileEditor.foundProfiles.length
                        ? qsTr("No profiles were found in the standard locations. Browse to a profile folder below.")
                        : "")
                })
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                FieldBox {
                    id: browserProfileName
                    width: Math.min(profileEditor.width, 310)
                    text: String(root.field.value ?? "")
                    placeholderText: qsTr("Default browser profile")
                    Accessible.name: root.field.label
                    onAccepted: root.saveLine(text.trim())
                }
                GlassButton {
                    text: qsTr("Apply")
                    enabled: browserProfileName.text.trim() !== String(root.field.value ?? "")
                    onClicked: root.saveLine(browserProfileName.text.trim())
                }
                GlassButton {
                    text: profileEditor.finding ? qsTr("Finding profiles…") : qsTr("Find profiles")
                    enabled: Boolean(root.cookieBrowser) && root.cookieBrowser !== "safari" && !profileEditor.finding
                    onClicked: profileEditor.discover()
                }
                GlassButton {
                    text: qsTr("Browse…")
                    Accessible.name: qsTr("Browse for the browser profile folder")
                    onClicked: profileFolder.open()
                }
                GlassButton {
                    visible: Boolean(root.field.value)
                    text: qsTr("Use default")
                    onClicked: root.commit("", {})
                }
            }

            GlassComboBox {
                Layout.fillWidth: true
                visible: profileEditor.detectedBrowser === root.cookieBrowser && count > 0
                model: profileEditor.foundProfiles
                textRole: "label"
                valueRole: "value"
                currentIndex: root.choiceIndex(profileEditor.foundProfiles, root.field.value, -1)
                displayText: currentIndex < 0 ? qsTr("Choose a detected profile") : currentText
                Accessible.name: qsTr("Detected browser profiles")
                onActivated: root.commit(currentValue, {})
            }

            Label {
                Layout.fillWidth: true
                visible: profileEditor.detectedBrowser === root.cookieBrowser && text.length > 0
                text: profileEditor.problem
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }

            FolderDialog {
                id: profileFolder
                title: qsTr("Choose the browser profile folder")
                onAccepted: {
                    const path = engine.localPath(selectedFolder)
                    if (path) root.commit(path, {})
                }
            }
        }
    }

    Component {
        id: expandButton
        GlassButton {
            text: root.expanded ? qsTr("Close editor") : qsTr("Edit…")
            checkable: true
            checked: root.expanded
            onClicked: root.expanded = !root.expanded
        }
    }

    Loader {
        Layout.fillWidth: true
        active: root.expanded && root.complex && !root.unavailable && !root.browserCapture
        sourceComponent: root.sounds ? soundControl : root.kind === "table" ? tableControl : root.kind === "lines" || root.kind === "multiline" ? linesControl : regionalControl
    }

    GlassButton {
        visible: root.field.defaultValue !== undefined
        Layout.alignment: Qt.AlignRight
        text: qsTr("Restore default")
        onClicked: root.commit(root.field.defaultValue, {})
    }

    Component {
        id: linesControl
        ColumnLayout {
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 108
                clip: true
                contentWidth: availableWidth
                TextArea {
                id: lines
                text: root.kind === "multiline" ? String(root.field.value || "") : (root.field.value || []).join("\n")
                placeholderText: root.kind === "multiline" ? qsTr("Separate entries with spaces") : qsTr("One address per line")
                color: root.colors.text
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                Accessible.name: root.field.label
                background: GlassSurface { role: "field" }
                }
            }

            GlassButton {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Save list")
                enabled: lines.text !== (root.kind === "multiline" ? String(root.field.value || "") : (root.field.value || []).join("\n"))
                onClicked: root.commit(root.kind === "multiline" ? lines.text.trim().replace(/\s+/g, " ") : lines.text.split(/\r?\n/).map(line => line.trim()).filter(Boolean), {})
            }
        }
    }

    Component {
        id: soundControl
        ColumnLayout {
            id: soundEditor
            property int selectedEvent: 0
            property string previewError: ""
            property bool previewPending: false
            property bool loadingCue: false
            readonly property var cues: [
                {id: "download-complete", label: qsTr("Completion chime")},
                {id: "download-failed", label: qsTr("Failure tone")},
                {id: "queue-started", label: qsTr("Queue start chime")},
                {id: "queue-stopped", label: qsTr("Queue stop chime")}
            ]
            enabled: !loadingCue

            function useBuiltIn(index) {
                loadingCue = true
                previewError = ""
                engine.request({local: "installNotificationCue", cue: cues[index].id}, function(path, error) {
                    soundEditor.loadingCue = false
                    if (error || !path) {
                        soundEditor.previewError = error || qsTr("Could not load the built-in sound.")
                        return
                    }
                    root.changeSound(index, true, path)
                })
            }

            function playWhenReady() {
                if (!previewPending)
                    return
                if (soundPlayer.status === SoundEffect.Ready) {
                    previewPending = false
                    soundPlayer.play()
                } else if (soundPlayer.status === SoundEffect.Error) {
                    previewPending = false
                    previewError = qsTr("The sound could not be played. Choose an existing WAV file.")
                }
            }

            function preview(path) {
                const url = WindowAppearance.fileUrl(path)
                previewError = ""
                if (!url || !/\.wav$/i.test(path)) {
                    previewError = qsTr("Choose an existing WAV sound file.")
                    return
                }
                soundPlayer.stop()
                previewPending = true
                soundPlayer.source = url
                playWhenReady()
            }

            SoundEffect {
                id: soundPlayer
                onStatusChanged: soundEditor.playWhenReady()
            }

            Repeater {
                model: root.soundEvents
                delegate: ColumnLayout {
                    id: soundRow
                    required property int index
                    required property string modelData
                    readonly property var entry: root.cells[index] || [false, ""]
                    readonly property string path: String(entry[1] ?? "")
                    readonly property var cue: soundEditor.cues[index]
                    readonly property bool builtIn: path.replace(/\\/g, "/")
                        .endsWith("/notification-sounds/auralis-" + cue.id + ".wav")
                    Layout.fillWidth: true
                    spacing: 3

                    GlassSwitch {
                        text: soundRow.modelData
                        checked: Boolean(soundRow.entry[0])
                        onToggled: root.changeSound(soundRow.index, checked, soundRow.path)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: soundRow.builtIn ? soundRow.cue.label
                                : soundRow.path ? soundRow.path.split(/[\\/]/).pop() : qsTr("No sound selected")
                            color: root.colors.muted
                            elide: Text.ElideMiddle
                            ToolTip.visible: soundPathHover.hovered && Boolean(soundRow.path)
                            ToolTip.text: soundRow.path
                            HoverHandler { id: soundPathHover }
                        }
                        GlassButton {
                            text: qsTr("Use built-in")
                            Accessible.name: qsTr("Use built-in sound for %1").arg(soundRow.modelData)
                            onClicked: soundEditor.useBuiltIn(soundRow.index)
                        }
                        GlassButton {
                            text: qsTr("Browse…")
                            Accessible.name: qsTr("Choose sound for %1").arg(soundRow.modelData)
                            onClicked: {
                                soundEditor.selectedEvent = soundRow.index
                                chooseSound.open()
                            }
                        }
                        GlassButton {
                            text: qsTr("Preview")
                            Accessible.name: qsTr("Preview sound for %1").arg(soundRow.modelData)
                            enabled: Boolean(soundRow.path) && !soundEditor.previewPending
                            onClicked: soundEditor.preview(soundRow.path)
                        }
                        GlassButton {
                            text: qsTr("Clear")
                            Accessible.name: qsTr("Clear sound for %1").arg(soundRow.modelData)
                            enabled: Boolean(soundRow.path)
                            onClicked: root.changeSound(soundRow.index, false, "")
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: soundEditor.previewError
                color: root.colors.destructive
                wrapMode: Text.WordWrap
            }

            GlassButton {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Save sounds")
                enabled: JSON.stringify(root.cells) !== JSON.stringify(root.field.value)
                onClicked: root.commit(root.cells, {})
            }

            FileDialog {
                id: chooseSound
                title: qsTr("Choose a notification sound")
                nameFilters: [qsTr("WAV sound files (*.wav)")]
                onAccepted: {
                    const path = engine.localPath(selectedFile)
                    if (path) root.changeSound(soundEditor.selectedEvent, true, path)
                }
            }
        }
    }

    Component {
        id: tableControl
        ColumnLayout {
            id: tableEditor
            readonly property var columns: root.field.columns || []

            Repeater {
                model: root.cells
                delegate: RowLayout {
                    id: tableRow
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true

                    Repeater {
                        model: tableEditor.columns
                        delegate: Loader {
                            id: cell
                            required property int index
                            required property var modelData
                            readonly property int row: tableRow.index
                            readonly property var entry: tableRow.modelData[cell.index]
                            Layout.fillWidth: modelData.kind !== "boolean"
                            Layout.preferredWidth: modelData.kind === "boolean" ? 82 : 150

                            function update(value) {
                                root.cells[row][index] = value
                            }

                            sourceComponent: modelData.kind === "boolean" ? rowCheck : modelData.options ? rowChoice
                                : root.field.key === "category_dirs" && index === 1 ? rowPath : rowValue

                            Component {
                                id: rowCheck
                                CheckBox {
                                    text: cell.modelData.label
                                    checked: Boolean(cell.entry)
                                    palette.windowText: root.colors.text
                                    onToggled: cell.update(checked)
                                }
                            }

                            Component {
                                id: rowChoice
                                GlassComboBox {
                                    enabled: root.field.key !== "category_dirs"
                                    model: cell.modelData.options
                                    textRole: "label"
                                    valueRole: "value"
                                    currentIndex: root.choiceIndex(cell.modelData.options, cell.entry, -1)
                                    Accessible.name: cell.modelData.label
                                    onActivated: cell.update(currentValue)
                                }
                            }

                            Component {
                                id: rowPath
                                RowLayout {
                                    FieldBox {
                                        id: location
                                        Layout.fillWidth: true
                                        text: String(cell.entry ?? "")
                                        placeholderText: cell.modelData.label
                                        Accessible.name: cell.modelData.label
                                        onTextEdited: cell.update(text)
                                    }
                                    GlassButton {
                                        text: qsTr("Browse…")
                                        onClicked: chooseFolder.open()
                                    }
                                    FolderDialog {
                                        id: chooseFolder
                                        title: qsTr("Choose a category folder")
                                        onAccepted: {
                                            location.text = engine.localPath(selectedFolder)
                                            cell.update(location.text)
                                        }
                                    }
                                }
                            }

                            Component {
                                id: rowValue
                                FieldBox {
                                    text: String(cell.entry ?? "")
                                    font.family: cell.modelData.kind === "number" && text.length
                                        ? root.Window.window?.numeralInputFamily?.() || "" : root.Window.window?.font.family || ""
                                    placeholderText: cell.modelData.label
                                    Accessible.name: cell.modelData.label
                                    echoMode: cell.modelData.kind === "password" ? TextInput.Password : TextInput.Normal
                                    inputMethodHints: cell.modelData.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
                                    validator: cell.modelData.kind === "number" ? cellInteger : null
                                    onTextEdited: {
                                        if (acceptableInput) cell.update(cell.modelData.kind === "number" ? Number(text) : text)
                                    }
                                    IntValidator { id: cellInteger; bottom: 0 }
                                }
                            }
                        }
                    }

                    GlassButton {
                        text: qsTr("Remove")
                        visible: !root.field.fixed
                        onClicked: {
                            const rows = root.cells.slice()
                            rows.splice(tableRow.index, 1)
                            root.cells = rows
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: root.field.key === "site_logins"
                text: qsTr("A blank password keeps the saved password for the same site and username.")
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                GlassButton {
                    visible: !root.field.fixed
                    text: qsTr("Add row")
                    onClicked: root.cells = root.cells.concat([tableEditor.columns.map(root.defaultCell)])
                }
                Item { Layout.fillWidth: true }
                GlassButton {
                    text: qsTr("Save table")
                    onClicked: root.commit(root.cells, {})
                }
            }
        }
    }

    Component {
        id: regionalControl
        ColumnLayout {
            CheckBox {
                text: qsTr("Use custom date and time format")
                checked: Boolean(root.regional.custom)
                onToggled: root.regional = Object.assign({}, root.regional, {custom: checked})
            }
            GlassComboBox {
                Layout.fillWidth: true
                enabled: root.regional.custom
                model: [qsTr("Day / Month / Year"), qsTr("Month / Day / Year"), qsTr("Year / Month / Day")]
                currentIndex: ["dmy", "mdy", "ymd"].indexOf(root.regional.order)
                Accessible.name: qsTr("Date order")
                onActivated: index => root.regional = Object.assign({}, root.regional, {order: ["dmy", "mdy", "ymd"][index]})
            }
            CheckBox {
                text: qsTr("24-hour clock")
                enabled: root.regional.custom
                checked: Boolean(root.regional.clock24)
                onToggled: root.regional = Object.assign({}, root.regional, {clock24: checked})
            }
            GlassComboBox {
                Layout.fillWidth: true
                enabled: root.regional.custom
                model: [qsTr("Sunday"), qsTr("Monday"), qsTr("Tuesday"), qsTr("Wednesday"), qsTr("Thursday"), qsTr("Friday"), qsTr("Saturday")]
                currentIndex: root.regional.week_start ?? 0
                Accessible.name: qsTr("First day of the week")
                onActivated: index => root.regional = Object.assign({}, root.regional, {week_start: index})
            }
            GlassButton {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Save format")
                onClicked: root.commit(root.regional, {})
            }
        }
    }
}
