pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: root
    objectName: "settingsUpdates"

    property string updatePresentation: "toast"
    property bool automaticChecks: true
    property var release: null
    property bool backdropAvailable: false
    signal updatePresentationRequested(string value)
    signal automaticChecksRequested(bool value)
    signal updateCheckRequested()
    signal updateDetailsRequested()

    readonly property var colors: MaterialTheme.palette
    readonly property bool supportsUpdates: Qt.platform.os === "windows"
    readonly property bool currentPage: visible && Boolean(Window.window?.visible)
        && Window.window.visibility !== Window.Minimized && engine.ready
    readonly property string releasePage: "https://github.com/4ls4mi/Auralis-Download-Manager/releases"
    readonly property var presentationOptions: [
        {label: qsTr("Show in Auralis only"), value: "quiet"},
        {label: qsTr("Auralis corner popup"), value: "toast"},
        {label: qsTr("Windows notification and Auralis corner popup"), value: "notify"},
        {label: qsTr("Open update details immediately"), value: "dialog"}
    ]
    readonly property var bundledNotes: [
        {version: "0.3.67", tag: "v0.3.67", publishedAt: "2026-11-23T02:44:45Z", notes:
            qsTr("Choose Classic, Normal, Gushing water or Jelly separately for progress, connection indicators and speed graphs. This release also added Chrome Web Store setup and more vivid action controls.")},
        {version: "0.3.66", tag: "v0.3.66", publishedAt: "2026-11-23T01:42:34Z", notes:
            qsTr("Private transfers stay hidden from paired remote clients. Browser handoff and file handling were tightened, and the updater verifies its release source and installer. Qt was updated to 6.11.3.")},
        {version: "0.3.65", tag: "v0.3.65", publishedAt: "2026-11-22T20:01:12Z", notes:
            qsTr("Download windows gained independent movement, and active progress windows can be resized. The completion window shows the exact file size and actions to open, move or drag it. Non-acrylic materials gained adjustable opacity.")}
    ]
    property var liveNotes: []
    property bool loadingNotes: false
    property bool couldNotRefresh: false
    property double lastHistoryRequest: 0
    readonly property var displayedNotes: {
        const notes = {}
        for (const item of bundledNotes)
            notes[item.version] = item
        for (const item of liveNotes) {
            if (validRelease(item))
                notes[item.version] = Object.assign({}, notes[item.version], item, {
                    notes: item.notes || notes[item.version]?.notes || "",
                    publishedAt: item.publishedAt || notes[item.version]?.publishedAt || ""
                })
        }
        return Object.values(notes).sort((left, right) => {
            const a = left.version.split(".").map(Number)
            const b = right.version.split(".").map(Number)
            return b[0] - a[0] || b[1] - a[1] || b[2] - a[2]
        }).slice(0, 3)
    }

    spacing: 12

    function validRelease(item) {
        return item && /^\d+\.\d+\.\d+$/.test(item.version)
            && (item.tag === "v" + item.version || item.tag === "V" + item.version || item.tag === item.version)
    }

    function loadHistory() {
        if (!supportsUpdates || !currentPage || loadingNotes || Date.now() - lastHistoryRequest < 300000)
            return
        lastHistoryRequest = Date.now()
        loadingNotes = true
        engine.request({shellAction: "update-history"}, function(result, error) {
            root.loadingNotes = false
            // QVariantList is array-like in QML, but Array.isArray returns false for it.
            const releases = result ? Array.from(result).filter(item => root.validRelease(item)) : []
            root.couldNotRefresh = Boolean(error) || releases.length === 0
            if (releases.length > 0)
                root.liveNotes = releases
        })
    }

    function releaseNotes(value) {
        return String(value || "").trim()
            .replace(/^[ \t]*#{1,6}[ \t]+/gm, "")
            .replace(/^[ \t]*[-*][ \t]+/gm, "• ")
            .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    }

    onCurrentPageChanged: if (currentPage) loadHistory()
    Component.onCompleted: if (currentPage) loadHistory()

    component Heading: Label {
        Layout.fillWidth: true
        color: root.colors.text
        font.pixelSize: TypographyScale.pixels(17)
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    component Copy: Label {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        color: root.colors.muted
        wrapMode: Text.Wrap
    }

    component Card: Frame {
        Layout.fillWidth: true
        padding: 13
        background: GlassSurface { role: "content"; backdropAvailable: root.backdropAvailable }
    }

    Card {
        ColumnLayout {
            width: parent.width
            spacing: 10

            Heading { text: qsTr("Auralis Download Manager") }
            Copy {
                objectName: "installedAuralisVersion"
                text: qsTr("Installed version %1").arg(engine.version)
            }
            Copy {
                visible: !root.supportsUpdates || Boolean(root.release?.version)
                text: !root.supportsUpdates ? qsTr("The installer updater is available on Windows.")
                    : qsTr("Auralis %1 is available.").arg(root.release?.version || "")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8
                GlassButton {
                    objectName: "settingsCheckForUpdates"
                    visible: root.supportsUpdates
                    text: qsTr("Check for updates")
                    filled: true
                    onClicked: root.updateCheckRequested()
                }
                GlassButton {
                    objectName: "settingsReviewUpdate"
                    visible: root.supportsUpdates && root.release?.state === "available"
                    text: qsTr("Review update")
                    onClicked: root.updateDetailsRequested()
                }
                GlassButton {
                    text: qsTr("Latest release on GitHub")
                    onClicked: Qt.openUrlExternally(root.releasePage + "/latest")
                }
            }

            Switch {
                visible: root.supportsUpdates
                text: qsTr("Check for Auralis updates automatically")
                checked: root.automaticChecks
                onToggled: root.automaticChecksRequested(checked)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.supportsUpdates
                Copy { text: qsTr("Update notification"); color: root.colors.text }
                GlassComboBox {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 270
                    model: root.presentationOptions
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: Math.max(0, root.presentationOptions.findIndex(choice => choice.value === root.updatePresentation))
                    enabled: root.automaticChecks
                    Accessible.name: qsTr("Update notification")
                    onActivated: root.updatePresentationRequested(currentValue)
                }
            }
        }
    }

    Heading { text: qsTr("About Auralis") }
    Card {
        ColumnLayout {
            width: parent.width
            spacing: 8
            Copy { text: qsTr("Auralis is an independent GPL-3.0 fork of Mister Download Manager (MDM). It shares the MDM download engine and pairs it with a Qt interface and customizable transfer indicators.") }
            Copy { text: qsTr("Direct downloads follow the familiar segmented-file workflow of Internet Download Manager (IDM), with multiple connections, pause and resume, queues, and speed limits. A separate transfer window shows connection activity and live speed.") }
            Copy { text: qsTr("Auralis also brings together torrent recovery and gallery downloads. If an eligible direct download is interrupted, it can verify saved pieces against a matching torrent and reuse them while BitTorrent fetches the missing data.") }
            Copy { text: qsTr("Send files from your browser, choose video or audio qualities on supported sites, or download a site gallery with gallery-dl.") }
            Copy { text: qsTr("Choose window materials and adjust progress, connection and graph colors and animations independently. Export appearance settings or back up download history and supported transfer files.") }
        }
    }

    Heading { text: qsTr("Recent release notes") }
    Copy {
        visible: root.loadingNotes || root.couldNotRefresh || !root.supportsUpdates
        text: root.loadingNotes ? qsTr("Checking GitHub for release notes…")
            : root.couldNotRefresh ? qsTr("Could not refresh from GitHub. Showing saved release notes.")
            : qsTr("Showing release notes bundled with Auralis.")
    }

    Repeater {
        model: root.displayedNotes
        delegate: Card {
            id: noteCard
            required property var modelData
            ColumnLayout {
                width: parent.width
                spacing: 7
                RowLayout {
                    Layout.fillWidth: true
                    Heading { text: qsTr("Auralis %1").arg(noteCard.modelData.version) }
                    GlassButton {
                        text: qsTr("View on GitHub")
                        Accessible.name: qsTr("View Auralis %1 on GitHub").arg(noteCard.modelData.version)
                        onClicked: {
                            if (root.validRelease(noteCard.modelData))
                                Qt.openUrlExternally(root.releasePage + "/tag/" + noteCard.modelData.tag)
                        }
                    }
                }
                Copy {
                    visible: text.length > 0
                    text: {
                        const date = new Date(noteCard.modelData.publishedAt || "")
                        return Number.isFinite(date.getTime()) ? Qt.formatDate(date, "d MMM yyyy") : ""
                    }
                }
                Copy {
                    text: root.releaseNotes(noteCard.modelData.notes) || qsTr("See GitHub for the full release notes.")
                }
            }
        }
    }
}
