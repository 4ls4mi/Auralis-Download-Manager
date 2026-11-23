pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: root

    required property var fontSettings
    property string draftEnglishFamily: fontSettings.englishFamily ?? ""
    property string draftArabicFamily: fontSettings.arabicFamily ?? ""
    property int draftSizePercent: fontSettings.fontSizePercent ?? 100
    property bool applyFailed: false
    readonly property bool previewActive: visible && (!Window.window || Window.window.visible)
    readonly property bool hasChanges: draftEnglishFamily !== (fontSettings.englishFamily ?? "")
        || draftArabicFamily !== (fontSettings.arabicFamily ?? "") || draftSizePercent !== (fontSettings.fontSizePercent ?? 100)
    readonly property var sizeOptions: Array.from(fontSettings.fontSizeChoices ?? [100], value => ({
        label: qsTr("%1%").arg(value), value: value
    }))
    readonly property int sizeIndex: Math.max(0, sizeOptions.findIndex(option => option.value === draftSizePercent))
    readonly property var colors: MaterialTheme.palette
    readonly property var englishCurated: ["Talina", "Milkyway", "Mochi Boom", "Qilka", "Qurova"]
    readonly property var arabicCurated: ["Kidzhood Arabic", "Tinta Arabic", "Madani Arabic",
        "Mahameru Arabic", "Gumela Arabic", "Tufuli Arabic", "Lutfey Arabic"]

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

    onPreviewActiveChanged: if (!previewActive) discardDraft()
    onDraftEnglishFamilyChanged: applyFailed = false
    onDraftArabicFamilyChanged: applyFailed = false
    onDraftSizePercentChanged: applyFailed = false

    function familyKey(name) {
        return name.toLowerCase().replace(/[^a-z0-9]/g, "")
    }

    function familyChoices(curated, installed) {
        const detected = new Map()
        for (const family of installed) {
            const key = familyKey(family)
            if (key && !detected.has(key))
                detected.set(key, family)
        }

        const options = [{label: qsTr("System default"), value: ""}]
        const missing = []
        const included = new Set()
        for (const name of curated) {
            const key = familyKey(name)
            const family = detected.get(key)
            if (family) {
                options.push({label: name, value: family})
                included.add(key)
            } else {
                missing.push(name)
            }
        }
        for (const family of installed) {
            if (family && !included.has(familyKey(family)))
                options.push({label: family, value: family})
        }
        return {options: options, missing: missing}
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
        required property var installed
        required property var curated
        required property string sampleTitle
        required property string sampleDetail
        required property string sampleStatus
        property bool rightToLeft: false
        readonly property var choices: root.familyChoices(curated, installed)
        readonly property int selectedIndex: Math.max(0, choices.options.findIndex(option => option.value === family))
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
            model: script.choices.options
            textRole: "label"
            valueRole: "value"
            currentIndex: script.selectedIndex
            Accessible.name: script.caption
            fontOptionPreview: family => ({
                text: script.sampleTitle,
                font: root.previewFont(family, 19, Font.DemiBold)
            })
            onActivated: script.familyRequested(currentValue)
        }

        Frame {
            Layout.fillWidth: true
            padding: 10
            background: GlassSurface { role: "field" }

            contentItem: ColumnLayout {
                spacing: 3
                Label {
                    objectName: script.rightToLeft ? "arabicFontPreview" : "englishFontPreview"
                    Layout.fillWidth: true
                    text: script.sampleTitle
                    textFormat: Text.PlainText
                    font: root.previewFont(script.family, 20, Font.DemiBold)
                    color: root.colors.text
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: script.sampleDetail
                    textFormat: Text.PlainText
                    font: root.previewFont(script.family, 13, Font.Normal)
                    color: root.colors.muted
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.Wrap
                }
                Label {
                    Layout.fillWidth: true
                    text: script.sampleStatus
                    textFormat: Text.PlainText
                    font: root.previewFont(script.family, 12, Font.Medium)
                    color: root.colors.positive
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.Wrap
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: script.choices.missing.length > 0
            text: qsTr("Available after installation (%1).").arg(script.choices.missing.join(", "))
            textFormat: Text.PlainText
            color: root.colors.muted
            wrapMode: Text.Wrap
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
        GlassComboBox {
            objectName: "fontSizeChoice"
            Layout.preferredWidth: 135
            model: root.sizeOptions
            textRole: "label"
            valueRole: "value"
            currentIndex: root.sizeIndex
            Accessible.name: qsTr("Font size")
            onActivated: root.draftSizePercent = currentValue
        }
        Item { Layout.fillWidth: true }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= 540 ? 2 : 1
        columnSpacing: 14
        rowSpacing: 13

        ScriptFonts {
            caption: qsTr("English interface font")
            family: root.draftEnglishFamily
            installed: root.fontSettings.englishFonts
            curated: root.englishCurated
            sampleTitle: "Download queue"
            sampleDetail: "Archive.zip · 42 MB of 108 MB"
            sampleStatus: "Downloading · 3.2 MB/s"
            onFamilyRequested: value => root.draftEnglishFamily = value
        }

        ScriptFonts {
            caption: qsTr("Arabic interface font")
            family: root.draftArabicFamily
            installed: root.fontSettings.arabicFonts
            curated: root.arabicCurated
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
        text: qsTr("Install licensed font copies on this device, then reopen Auralis to use them here.")
        color: root.colors.muted
        wrapMode: Text.WordWrap
    }
}
