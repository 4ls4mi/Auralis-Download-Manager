pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: root

    property string section: "Advanced"
    property var helpers: null
    property bool loadingHelpers: false
    property bool helperRequest: false
    property string helperProblem: ""
    readonly property bool browserSection: section === "Browser Integration"
    readonly property bool hasWindowsIntegration: Qt.platform.os === "windows"
    readonly property bool browserSetupVisible: browserSection && hasWindowsIntegration && visible
        && Boolean(Window.window?.visible) && Window.window.visibility !== Window.Minimized
    readonly property bool installingHelper: Boolean(helpers && helpers.job && helpers.job.state === "installing")
    readonly property var colors: MaterialTheme.palette

    spacing: 14

    function loadHelpers() {
        if (browserSection || loadingHelpers)
            return
        loadingHelpers = true
        engine.request({query: "glass-helpers"}, function(result, error) {
            loadingHelpers = false
            if (error || !result) {
                if (!helpers)
                    helperProblem = error || qsTr("Could not load media helpers.")
                return
            }
            if (!helpers)
                helperProblem = ""
            helpers = result
        })
    }

    function installHelper(name) {
        if (helperRequest || installingHelper)
            return
        helperRequest = true
        helperProblem = ""
        engine.request({action: "glass-helpers", queue: JSON.stringify({name: name})}, function(result, error) {
            helperRequest = false
            if (error || !result || !result.ok)
                helperProblem = error || qsTr("Could not start the helper installation.")
            loadHelpers()
        })
    }

    Component.onCompleted: if (visible) loadHelpers()
    onVisibleChanged: if (visible) loadHelpers()
    onSectionChanged: if (visible) loadHelpers()
    Timer {
        interval: 1500
        repeat: true
        running: root.visible && !root.browserSection
        onTriggered: root.loadHelpers()
    }

    BrowserSetupOptions {
        objectName: "settingsBrowserSetupOptions"
        Layout.fillWidth: true
        visible: root.browserSection
        monitoring: root.browserSetupVisible
        showManualTools: true
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !root.browserSection
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: qsTr("Video and gallery helpers")
            color: root.colors.text
            font.pixelSize: TypographyScale.pixels(17)
            font.weight: Font.DemiBold
        }

        Repeater {
            model: root.helpers ? root.helpers.tools : []

            delegate: RowLayout {
                id: tool
                required property var modelData
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        text: tool.modelData.name
                        color: root.colors.text
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: tool.modelData.version
                            ? qsTr("%1 · %2").arg(tool.modelData.version).arg(tool.modelData.path)
                            : qsTr("Not installed")
                        color: root.colors.muted
                        elide: Text.ElideMiddle
                    }
                }

                GlassButton {
                    text: tool.modelData.version ? qsTr("Check for update") : qsTr("Install")
                    enabled: !root.helperRequest && !root.installingHelper
                    onClicked: root.installHelper(tool.modelData.name)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: Boolean(root.helpers && root.helpers.job) || root.helperRequest || (root.loadingHelpers && !root.helpers)
            wrapMode: Text.WordWrap
            color: root.colors.muted
            text: {
                const job = root.helpers && root.helpers.job
                if (root.helperRequest) return qsTr("Starting helper installation…")
                if (!job) return qsTr("Checking installed helpers…")
                if (job.state === "installing") return qsTr("Installing %1…").arg(job.name)
                if (job.state === "ready") return qsTr("%1 is ready.").arg(job.name)
                return qsTr("%1 · %2").arg(job.name).arg(job.state)
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.helperProblem.length > 0
            text: root.helperProblem
            color: root.colors.destructive
            wrapMode: Text.WordWrap
        }

    }
}
