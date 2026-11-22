import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: root

    property var accounts: []
    property var services: []
    property var signIn: null
    property string selectedService: ""
    property string selectedMethod: "token"
    property string problem: ""
    property bool adding: false
    property bool loaded: false
    property bool loading: false
    property bool busy: false
    readonly property bool blocked: busy || loading
    readonly property var colors: MaterialTheme.palette
    readonly property var service: services.find(service => service.value === selectedService)
    readonly property bool working: Boolean(signIn && ["busy", "code"].includes(signIn.kind))
    readonly property bool verified: Boolean(signIn && signIn.kind === "ready")

    function load() {
        if (loading)
            return
        loading = true
        engine.request({query: "glass-accounts"}, function(result, error) {
            loading = false
            if (error || !result) {
                if (!loaded)
                    problem = error || qsTr("Could not load service accounts.")
                return
            }
            accounts = result.accounts || []
            services = result.services || []
            signIn = result.signin || null
            if (!services.some(service => service.value === selectedService))
                selectedService = services.length ? services[0].value : ""
            if (!loaded && signIn)
                adding = true
            if (!loaded)
                problem = ""
            loaded = true
        })
    }

    function request(payload, callback) {
        if (blocked)
            return
        busy = true
        problem = ""
        engine.request({action: "glass-account", queue: JSON.stringify(payload)}, function(result, error) {
            busy = false
            if (error || !result || !result.ok) {
                problem = error || qsTr("Could not update the service account.")
                load()
                return
            }
            if (callback)
                callback()
            signIn = null
            load()
        })
    }

    function clearCredentials() {
        tokenInput.clear()
        passwordInput.clear()
        usernameInput.clear()
    }

    Component.onCompleted: if (visible) load()
    onVisibleChanged: if (visible) load()

    Timer {
        interval: 1400
        repeat: true
        running: root.visible && root.adding && !root.blocked
        onTriggered: root.load()
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            Layout.fillWidth: true
            text: qsTr("Connected services")
            font.pixelSize: 17
            font.weight: Font.DemiBold
            color: root.colors.text
        }

        GlassButton {
            visible: !root.adding
            text: qsTr("Add account")
            enabled: root.loaded && !root.blocked && root.services.length > 0
            onClicked: {
                root.clearCredentials()
                root.problem = ""
                root.selectedMethod = "token"
                root.adding = true
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !root.adding && root.accounts.length === 0
        text: root.loaded ? qsTr("No service accounts connected.") : qsTr("Loading service accounts…")
        color: root.colors.muted
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.adding ? [] : root.accounts

        delegate: RowLayout {
            id: entry
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 8

            Switch {
                checked: entry.modelData.enabled
                enabled: !root.blocked
                Accessible.name: qsTr("Enable %1").arg(entry.modelData.service)
                onClicked: root.request({operation: "update", id: entry.modelData.id, enabled: checked})
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: entry.modelData.user
                        ? qsTr("%1 · %2").arg(entry.modelData.service).arg(entry.modelData.user)
                        : entry.modelData.service
                    color: root.colors.text
                }

                Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    elide: Text.ElideRight
                    text: entry.modelData.state || ""
                    font.pixelSize: 11
                    color: root.colors.muted
                }
            }

            GlassButton {
                text: "↑"
                Accessible.name: qsTr("Move account up")
                enabled: !root.blocked && entry.index > 0
                onClicked: root.request({operation: "up", id: entry.modelData.id})
            }
            GlassButton {
                text: "↓"
                Accessible.name: qsTr("Move account down")
                enabled: !root.blocked && entry.index + 1 < root.accounts.length
                onClicked: root.request({operation: "down", id: entry.modelData.id})
            }
            GlassButton {
                text: qsTr("Remove")
                danger: true
                enabled: !root.blocked
                onClicked: {
                    confirmRemoval.accountId = entry.modelData.id
                    confirmRemoval.accountName = entry.modelData.service
                    confirmRemoval.open()
                }
            }
        }
    }

    DetachedConfirmation {
        id: confirmRemoval
        objectName: "accountRemovalWindow"
        hostWindow: root.Window.window
        property var accountId
        property string accountName
        title: qsTr("Remove service account")
        message: qsTr("Remove the saved %1 account from Auralis?").arg(accountName)
        confirmText: qsTr("Remove account")
        destructive: true
        onConfirmed: root.request({operation: "remove", id: accountId})
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.adding
        spacing: 8

        GlassComboBox {
            Layout.fillWidth: true
            Accessible.name: qsTr("Service")
            model: root.services
            textRole: "name"
            valueRole: "value"
            currentIndex: root.services.findIndex(service => service.value === root.selectedService)
            enabled: !root.working && !root.verified && !root.blocked
            onActivated: {
                root.selectedService = currentValue
                root.selectedMethod = "token"
                root.clearCredentials()
            }
        }

        GlassComboBox {
            id: methods
            Layout.fillWidth: true
            Accessible.name: qsTr("Sign-in method")
            model: {
                const options = [{name: qsTr("API token or key"), value: "token"}]
                if (root.service && root.service.code)
                    options.push({name: qsTr("Sign in through browser"), value: "code"})
                if (root.selectedService === "MegaDebrid")
                    options.push({name: qsTr("Username and password"), value: "password"})
                return options
            }
            textRole: "name"
            valueRole: "value"
            currentIndex: model.findIndex(method => method.value === root.selectedMethod)
            enabled: !root.working && !root.verified && !root.blocked
            onActivated: {
                root.selectedMethod = currentValue
                root.clearCredentials()
            }
        }

        TextField {
            id: tokenInput
            Layout.fillWidth: true
            visible: root.selectedMethod === "token" && !root.verified
            enabled: !root.working && !root.blocked
            placeholderText: qsTr("API token")
            Accessible.name: placeholderText
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData | Qt.ImhHiddenText
            echoMode: TextInput.Password
            color: root.colors.text
            placeholderTextColor: root.colors.muted
            background: GlassSurface { role: "field" }
        }

        TextField {
            id: usernameInput
            Layout.fillWidth: true
            visible: root.selectedMethod === "password" && !root.verified
            enabled: !root.working && !root.blocked
            placeholderText: qsTr("Username")
            Accessible.name: placeholderText
            selectByMouse: true
            color: root.colors.text
            placeholderTextColor: root.colors.muted
            background: GlassSurface { role: "field" }
        }

        TextField {
            id: passwordInput
            Layout.fillWidth: true
            visible: root.selectedMethod === "password" && !root.verified
            enabled: !root.working && !root.blocked
            placeholderText: qsTr("Password")
            Accessible.name: placeholderText
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData | Qt.ImhHiddenText
            echoMode: TextInput.Password
            color: root.colors.text
            placeholderTextColor: root.colors.muted
            background: GlassSurface { role: "field" }
        }

        Label {
            Layout.fillWidth: true
            visible: text.length > 0
            wrapMode: Text.WordWrap
            color: root.signIn && root.signIn.kind === "error" ? root.colors.destructive : root.colors.muted
            text: {
                const state = root.signIn
                if (!state) return ""
                if (state.kind === "busy") return qsTr("Checking account…")
                if (state.kind === "code")
                    return qsTr("Enter %1 in your browser. This code expires in %2 seconds.")
                        .arg(state.code).arg(state.seconds)
                if (state.kind === "ready") return qsTr("Signed in as %1 · %2").arg(state.user).arg(state.state)
                if (state.kind === "error") return state.message
                return ""
            }
        }

        GlassButton {
            visible: Boolean(root.signIn && root.signIn.kind === "code"
                             && String(root.signIn.page || "").startsWith("https://"))
            text: qsTr("Open sign-in page")
            onClicked: Qt.openUrlExternally(root.signIn.page)
        }

        RowLayout {
            Layout.fillWidth: true

            GlassButton {
                text: qsTr("Cancel")
                enabled: !root.blocked
                onClicked: root.request({operation: "cancel"}, function() {
                    root.clearCredentials()
                    root.adding = false
                })
            }

            Item { Layout.fillWidth: true }

            GlassButton {
                text: root.verified ? qsTr("Save account") : qsTr("Sign in")
                enabled: !root.blocked && !root.working && Boolean(root.service) && (root.verified
                    || root.selectedMethod === "code"
                    || (root.selectedMethod === "token" && tokenInput.text.trim().length > 0)
                    || (root.selectedMethod === "password" && usernameInput.text.trim().length > 0
                        && passwordInput.text.length > 0))
                onClicked: {
                    if (root.verified) {
                        root.request({operation: "save"}, function() {
                            root.clearCredentials()
                            root.adding = false
                        })
                    } else {
                        root.request({
                            operation: "signin",
                            service: root.selectedService,
                            method: root.selectedMethod,
                            token: tokenInput.text.trim(),
                            user: usernameInput.text.trim(),
                            password: passwordInput.text
                        }, root.clearCredentials)
                    }
                }
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.problem.length > 0
        text: root.problem
        color: root.colors.destructive
        wrapMode: Text.WordWrap
    }
}
