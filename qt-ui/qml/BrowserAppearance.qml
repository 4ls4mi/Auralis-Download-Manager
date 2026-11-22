import QtQuick

QtObject {
    id: root

    required property var backend
    property string published: ""
    property bool publishing: false
    property bool pending: false

    function profile(id) {
        const material = MaterialTheme.profile(id)
        const hex = color => WindowAppearance.colorText(MaterialTheme.rgba(color, 1))
        return {
            id: id,
            label: material.name,
            light: material.light,
            opaque: MaterialTheme.opacityFor(id) >= 1,
            radius: Math.max(0, Math.min(24, Math.round(material.radius))),
            colors: {
                background: hex(material.background),
                surface: hex(material.roleFaces?.card || material.buttonFace || material.background),
                text: hex(material.text),
                muted: hex(material.muted),
                accent: hex(material.accent),
                border: hex(material.surfaceLine || material.divider),
                positive: hex(material.positive),
                caution: hex(material.caution),
                destructive: hex(material.destructive)
            }
        }
    }

    function publish() {
        if (!WindowAppearance.loaded)
            return
        if (publishing) {
            pending = true
            return
        }
        const appearance = {
            version: 1,
            current: profile(MaterialTheme.current),
            themes: MaterialTheme.materials.map(entry => profile(entry.id))
        }
        const snapshot = JSON.stringify(appearance)
        if (snapshot === published)
            return
        publishing = true
        backend.request({local: "publishBrowserAppearance", appearance: appearance}, (result, error) => {
            publishing = false
            if (!error && result === true)
                published = snapshot
            if (pending) {
                pending = false
                publishTimer.restart()
            }
        })
    }

    property Timer publishTimer: Timer {
        interval: 150
        onTriggered: root.publish()
    }

    property Connections materialChanges: Connections {
        target: MaterialTheme
        function onPaletteChanged() { root.publishTimer.restart() }
        function onMaterialsChanged() { root.publishTimer.restart() }
        function onTranslucencyChanged() { root.publishTimer.restart() }
    }

    property Connections preferenceChanges: Connections {
        target: WindowAppearance
        function onLoadedChanged() { root.publishTimer.restart() }
    }

    Component.onCompleted: publishTimer.start()
}
