pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: root

    required property var fontSettings
    property string draftEnglishFamily: fontSettings.englishFamily ?? ""
    property string draftArabicFamily: fontSettings.arabicFamily ?? ""
    property int draftSizePercent: fontSettings.fontSizePercent ?? 100
    property bool applyFailed: false
    property string fontProblem: ""
    property bool fontImported: false
    readonly property bool previewActive: visible && (!Window.window || Window.window.visible)
    readonly property bool hasChanges: draftEnglishFamily !== (fontSettings.englishFamily ?? "")
        || draftArabicFamily !== (fontSettings.arabicFamily ?? "") || draftSizePercent !== (fontSettings.fontSizePercent ?? 100)
    readonly property var colors: MaterialTheme.palette

    spacing: 13

    function discardDraft() {
        draftEnglishFamily = fontSettings.englishFamily ?? ""
        draftArabicFamily = fontSettings.arabicFamily ?? ""
        draftSizePercent = fontSettings.fontSizePercent ?? 100
        applyFailed = false
    }

    function applyDraft() {
        if (!hasChanges)
            return
        applyFailed = !fontSettings.applyFontPreferences(draftEnglishFamily, draftArabicFamily, draftSizePercent)
        if (!applyFailed)
            discardDraft()
    }

    onPreviewActiveChanged: {
        if (!previewActive) {
            discardDraft()
            fontProblem = ""
            fontImported = false
        }
    }
    onDraftEnglishFamilyChanged: applyFailed = false
    onDraftArabicFamilyChanged: applyFailed = false
    onDraftSizePercentChanged: applyFailed = false

    function familyChoices(fontOptions) {
        return [{label: qsTr("System default"), value: "", available: true}].concat(
            Array.from(fontOptions ?? [], entry => ({
                label: entry.available ? entry.label : qsTr("%1 (not installed)").arg(entry.label),
                value: entry.value,
                available: entry.available
            })))
    }

    function previewFont(family, size, weight) {
        const selected = fontSettings.previewFont(family)
        return Qt.font({family: selected.family, pixelSize: Math.max(1, Math.round(size * draftSizePercent / 100)),
            weight: weight})
    }

    component ScriptFonts: ColumnLayout {
        id: script

        required property string caption
        required property string family
        required property var fontOptions
        required property string sampleTitle
        required property string sampleDetail
        required property string sampleStatus
        property bool rightToLeft: false
        readonly property var choices: root.familyChoices(fontOptions)
        readonly property int selectedIndex: Math.max(0, choices.findIndex(option => option.value === family))
        signal familyRequested(string value)

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        spacing: 6

        Label {
            Layout.fillWidth: true
            text: script.caption
            color: root.colors.text
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        GlassComboBox {
            objectName: script.rightToLeft ? "arabicFontChoice" : "englishFontChoice"
            Layout.fillWidth: true
            model: script.choices
            textRole: "label"
            valueRole: "value"
            currentIndex: script.selectedIndex
            Accessible.name: script.caption
            optionAvailable: family => script.choices.some(option => option.value === family && option.available)
            fontOptionPreview: family => ({
                text: script.sampleTitle,
                font: root.previewFont(family, 19, Font.DemiBold)
            })
            onActivated: {
                if (optionAvailable(currentValue))
                    script.familyRequested(currentValue)
                else
                    currentIndex = Qt.binding(() => script.selectedIndex)
            }
        }

        Frame {
            Layout.fillWidth: true
            padding: 10
            background: GlassSurface { role: "field" }

            contentItem: ColumnLayout {
                spacing: 3
                NumeralLabel {
                    objectName: script.rightToLeft ? "arabicFontPreview" : "englishFontPreview"
                    Layout.fillWidth: true
                    valueText: script.sampleTitle
                    font: root.previewFont(script.family, 20, Font.DemiBold)
                    color: root.colors.text
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.WordWrap
                }
                NumeralLabel {
                    Layout.fillWidth: true
                    valueText: script.sampleDetail
                    font: root.previewFont(script.family, 13, Font.Normal)
                    color: root.colors.muted
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.Wrap
                }
                NumeralLabel {
                    Layout.fillWidth: true
                    valueText: script.sampleStatus
                    font: root.previewFont(script.family, 12, Font.Medium)
                    color: root.colors.positive
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        text: qsTr("Preview both languages here, then choose Apply font to update Auralis.")
        color: root.colors.muted
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        Label {
            text: qsTr("Font size")
            color: root.colors.text
            font.weight: Font.DemiBold
        }
        GlassSlider {
            objectName: "fontSizeChoice"
            Layout.fillWidth: true
            from: root.fontSettings.fontSizeMinimum ?? 85
            to: root.fontSettings.fontSizeMaximum ?? 130
            stepSize: 1
            snapMode: Slider.SnapAlways
            value: root.draftSizePercent
            palette.highlight: root.colors.accent
            Accessible.name: qsTr("Font size")
            onMoved: root.draftSizePercent = Math.round(value)
        }
        NumeralLabel {
            valueText: qsTr("%1%").arg(root.draftSizePercent)
            color: root.colors.text
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= 540 ? 2 : 1
        columnSpacing: 14
        rowSpacing: 13

        ScriptFonts {
            caption: qsTr("English interface font")
            family: root.draftEnglishFamily
            fontOptions: root.fontSettings.englishFontOptions
            sampleTitle: "Download queue"
            sampleDetail: "Archive.zip · 42 MB of 108 MB"
            sampleStatus: "Downloading · 3.2 MB/s"
            onFamilyRequested: value => root.draftEnglishFamily = value
        }

        ScriptFonts {
            caption: qsTr("Arabic interface font")
            family: root.draftArabicFamily
            fontOptions: root.fontSettings.arabicFontOptions
            rightToLeft: true
            sampleTitle: "قائمة التنزيلات"
            sampleDetail: "ملف مضغوط · ٤٢ من ١٠٨ ميغابايت"
            sampleStatus: "جارٍ التنزيل · ٣٫٢ ميغابايت/ثانية"
            onFamilyRequested: value => root.draftArabicFamily = value
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        GlassButton {
            objectName: "applyFontPreferences"
            text: qsTr("Apply font")
            accent: root.colors.accent
            filled: true
            enabled: root.hasChanges
            onClicked: root.applyDraft()
        }
        GlassButton {
            objectName: "discardFontDraft"
            text: qsTr("Discard changes")
            enabled: root.hasChanges
            onClicked: root.discardDraft()
        }
        GlassButton {
            objectName: "importInterfaceFont"
            text: qsTr("Import font file…")
            onClicked: importFontFile.open()
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.applyFailed
        text: qsTr("Auralis could not apply these font settings.")
        color: root.colors.destructive
        wrapMode: Text.WordWrap
    }

    Label {
        Layout.fillWidth: true
        visible: root.fontImported || root.fontProblem.length > 0
        text: root.fontProblem || qsTr("Font imported. Select it, then choose Apply font.")
        textFormat: Text.PlainText
        color: root.fontProblem ? root.colors.destructive : root.colors.positive
        wrapMode: Text.WordWrap
    }

    Label {
        Layout.fillWidth: true
        text: qsTr("Import a TTF or OTF file you are licensed to use.")
        color: root.colors.muted
        wrapMode: Text.WordWrap
    }

    FileDialog {
        id: importFontFile
        title: qsTr("Choose a licensed font file")
        nameFilters: [qsTr("Font files (*.ttf *.otf)")]
        onAccepted: {
            root.fontProblem = root.fontSettings.importFont(selectedFile)
            root.fontImported = !root.fontProblem
        }
    }
}
