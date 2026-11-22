import QtQuick
import QtQuick.Window
import QtMultimedia

Item {
    id: root

    required property Window hostWindow
    property string target: "details"
    readonly property var selection: WindowAppearance.background(target)
    readonly property bool desktopGlass: selection.mode === "desktop"
        && Qt.platform.os === "windows"
        && MaterialTheme.opacityFor(MaterialTheme.current) < 1
    readonly property bool backdropAvailable: desktopGlass || pictureReady || movieReady
    readonly property string media: selection.mode === "wallpaper" ? selection.media : ""
    readonly property bool video: /\.(mp4|webm|mov|m4v)(?:$|[?#])/i.test(media)
    readonly property bool pictureReady: !video && image.status === Image.Ready && Boolean(media)
    readonly property bool movieReady: video && player.hasVideo && player.error === MediaPlayer.NoError

    function refresh() {
        if (!hostWindow.visible) return
        engine.applyBackdrop(hostWindow, desktopGlass, !MaterialTheme.palette.light)
    }

    Component.onCompleted: Qt.callLater(refresh)
    onSelectionChanged: Qt.callLater(refresh)
    onDesktopGlassChanged: Qt.callLater(refresh)
    onBackdropAvailableChanged: {
        if (target === "main") MaterialTheme.backdropAvailable = backdropAvailable
    }

    Connections {
        target: root.hostWindow
        function onVisibleChanged() { Qt.callLater(root.refresh); root.syncPlayback() }
        function onActiveChanged() { Qt.callLater(root.refresh) }
    }

    Connections {
        target: MaterialTheme
        function onPaletteChanged() { Qt.callLater(root.refresh) }
    }

    function syncPlayback() {
        if (video && hostWindow.visible && !MaterialTheme.reducedMotion) player.play()
        else player.stop()
    }

    onMediaChanged: Qt.callLater(syncPlayback)

    Image {
        id: image
        anchors.fill: parent
        source: root.video ? "" : root.media
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
    }

    VideoOutput {
        id: output
        anchors.fill: parent
        visible: root.movieReady
        fillMode: VideoOutput.PreserveAspectCrop
    }

    MediaPlayer {
        id: player
        source: root.video ? root.media : ""
        videoOutput: output
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput { muted: true }
    }

    GlassSurface {
        anchors.fill: parent
        role: "window"
        radius: 0
        solidColor: root.selection.mode === "solid" && root.selection.color ?
            root.selection.color : MaterialTheme.palette.background
        backdropAvailable: root.backdropAvailable
    }
}
