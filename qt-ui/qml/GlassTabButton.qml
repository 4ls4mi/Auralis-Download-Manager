pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

TabButton {
    id: tab

    property string material: MaterialTheme.current
    property color accent: profile.accent
    readonly property var profile: MaterialTheme.profile(material)
    readonly property var finish: MaterialTheme.buttonFinishes[profile.finish]
    readonly property bool emphasized: enabled && (checked || hovered || visualFocus || down)
    readonly property color vividAccent: MaterialTheme.vividControlAccent(
        MaterialTheme.safeAccent(MaterialTheme.forcedAccent || accent, profile.light), profile.light)
    readonly property color pigment: MaterialTheme.mix(vividAccent, profile.secondary, finish.tint, 1)
    readonly property color face: MaterialTheme.mix(profile.buttonFace || profile.background, pigment,
        emphasized ? (down ? finish.press : hovered ? finish.hover : finish.selected) : finish.idle, 1)

    hoverEnabled: true
    palette.buttonText: emphasized ? MaterialTheme.contrastInk(face) : profile.ink

    background: Rectangle {
        id: plate
        anchors.margins: 2
        radius: Math.min(8, tab.profile.radius)
        opacity: tab.enabled ? 1 : .55
        border.width: tab.visualFocus ? 2 : 1
        border.color: tab.visualFocus ? tab.palette.buttonText
            : MaterialTheme.mix(tab.profile.edge, tab.pigment, tab.emphasized ? .76 : .37, 1)
        gradient: Gradient {
            GradientStop { position: 0; color: MaterialTheme.mix(tab.face, tab.profile.upper, tab.finish.crown * .54, 1) }
            GradientStop { position: tab.finish.shoulder; color: tab.face }
            GradientStop { position: .72; color: tab.face }
            GradientStop { position: 1; color: MaterialTheme.mix(tab.face, tab.profile.shade, tab.finish.depth, 1) }
        }

        ButtonLighting {
            anchors.fill: parent
            radius: plate.radius
            material: tab.material
            accent: tab.vividAccent
            emphasized: tab.emphasized
            pressed: tab.down
        }
    }
}
