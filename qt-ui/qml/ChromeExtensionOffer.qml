pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Frame {
    id: root
    objectName: "chromeExtensionOffer"

    required property Window hostWindow
    readonly property bool canCheck: hostWindow.active && hostWindow.visible && engine.ready && !preferences.dismissed
    property bool available: false
    property bool checking: false
    property bool opening: false
    property bool openedListing: false
    property string problem: ""

    visible: available && !preferences.dismissed
    padding: 8
    background: GlassSurface { role: "card" }

    Settings {
        id: preferences
        category: "BrowserIntegration"
        property bool dismissed: false
    }

    function check() {
        if (!canCheck || checking)
            return
        checking = true
        engine.request({local: "chromeExtensionStatus"}, function(status, error) {
            root.checking = false
            root.available = !error && Boolean(status && status.chromeDetected && status.storeUrl
                && !status.connectedRecently && !status.chromePreviouslyConnected)
        })
    }

    function openStore() {
        if (opening)
            return
        opening = true
        problem = ""
        engine.request({local: "openChromeExtensionStore"}, function(reply, error) {
            root.opening = false
            if (!error && reply && reply.ok)
                root.openedListing = true
            else
                root.problem = error || qsTr("Could not open the Chrome Web Store.")
        })
    }

    Component.onCompleted: check()
    onCanCheckChanged: if (canCheck) check()

    Timer {
        interval: 2500
        repeat: true
        running: root.visible && root.canCheck
        onTriggered: root.check()
    }

    contentItem: RowLayout {
        Label {
            Layout.fillWidth: true
            text: root.problem || (root.openedListing
                ? qsTr("Finish adding Auralis in Chrome, then open it from Chrome’s Extensions menu.")
                : qsTr("Add Auralis to Chrome to send browser downloads to the app and get extension updates automatically."))
            textFormat: Text.PlainText
            color: root.problem ? MaterialTheme.palette.destructive : MaterialTheme.palette.ink
            wrapMode: Text.WordWrap
        }
        GlassButton {
            text: qsTr("Open Chrome Web Store")
            enabled: !root.opening
            accent: MaterialTheme.palette.accent
            onClicked: root.openStore()
        }
        GlassButton {
            text: qsTr("Dismiss")
            onClicked: preferences.dismissed = true
        }
    }
}
