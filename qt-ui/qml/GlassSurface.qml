pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "MaterialGeometry.js" as Geometry

Item {
    id: surface
    clip: true

    property string material: MaterialTheme.current
    property string role: "content"
    property bool backdropAvailable: MaterialTheme.backdropAvailable
    property color accent: profile.accent
    property real emphasis: 0
    property color solidColor: profile.background
    property real radius: profile.radius
    property bool showReflection: role === "toolbar" && ["prism", "aero"].includes(profile.shape)

    readonly property var profile: MaterialTheme.profile(material)
    readonly property bool shell: role === "window" || role === "modal"
    readonly property bool recess: role === "content" || role === "field" || role === "sidebar"
    readonly property bool sculpted: ["bubble", "aero"].includes(profile.shape)
    readonly property bool stacked: ["smoke", "frost"].includes(profile.shape)
    readonly property bool faceted: ["prism", "ice", "chamfer"].includes(profile.shape)
    readonly property string outline: shell ? "square" : profile.shape
    readonly property real bevel: Math.max(1, Math.min(profile.bevel, height * .14, width * .10))
    readonly property real depth: Math.min(height / 3, 28 + profile.bevel)
    readonly property real reflectivity: profile.gloss * (role === "field" ? .54 : role === "button" ? .82 : 1)
    readonly property real backingAlpha: {
        const amount = MaterialTheme.opacityFor(material);
        if (shell)
            return backdropAvailable ? amount : 1;
        if (role === "field")
            return Math.min(.82, .18 + amount * .72);
        if (role === "button")
            return .05 + amount * .42 + Math.min(.3, emphasis * .42);
        return amount * (recess ? .32 : role === "toolbar" || role === "footer" ? .65 : .45);
    }
    readonly property color backing: shell && !backdropAvailable
        ? solidColor : MaterialTheme.tint(profile.background, backingAlpha)
    readonly property string framePath: Geometry.frame(.6, .6, width - 1.2, height - 1.2, radius, outline)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: surface.shell ? 1 : 1.15
            strokeColor: MaterialTheme.rgba(surface.profile.edge, .33 + .32 * surface.reflectivity)
            fillColor: surface.backing
            PathSvg { path: surface.framePath }
        }

        // Shading is concentrated in the top and lower bevel. The middle of
        // the pane exposes the same glass backing as the rest of the window.
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: surface.width * .08; y2: surface.height
                GradientStop { position: 0; color: MaterialTheme.rgba(surface.recess ? surface.profile.shade : surface.profile.upper, surface.recess ? .24 : .12 + .27 * surface.reflectivity) }
                GradientStop { position: .21; color: "transparent" }
                GradientStop { position: .70; color: "transparent" }
                GradientStop { position: 1; color: MaterialTheme.rgba(surface.profile.shade, surface.recess ? .24 : .36 * surface.reflectivity) }
            }
            PathSvg { path: surface.framePath }
        }

        ShapePath {
            strokeWidth: Math.max(1, surface.bevel * .56)
            strokeColor: MaterialTheme.rgba(surface.profile.shade, surface.recess ? .27 : .34)
            fillColor: "transparent"
            PathSvg {
                path: Geometry.frame(surface.bevel, surface.bevel, surface.width - 2 * surface.bevel,
                                     surface.height - 2 * surface.bevel, Math.max(0, surface.radius - surface.bevel), surface.outline)
            }
        }

        ShapePath {
            strokeWidth: Math.max(.6, surface.bevel * .28)
            strokeColor: MaterialTheme.rgba(surface.profile.secondary, .15 + surface.reflectivity * .22)
            fillColor: "transparent"
            PathSvg {
                path: Geometry.frame(surface.bevel + 1.7, surface.bevel + 1.7,
                                     surface.width - 2 * surface.bevel - 3.4, surface.height - 2 * surface.bevel - 3.4,
                                     Math.max(0, surface.radius - surface.bevel - 1), surface.outline)
            }
        }

        // A narrow colored return sets the depth and hue at the far side.
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: surface.width; y1: surface.height
                x2: surface.width * .68; y2: surface.height - surface.depth
                GradientStop { position: 0; color: MaterialTheme.rgba(surface.profile.secondary, .25 * surface.reflectivity) }
                GradientStop { position: .18; color: MaterialTheme.rgba(surface.profile.accent, .13 * surface.reflectivity) }
                GradientStop { position: .96; color: "transparent" }
            }
            PathSvg { path: surface.framePath }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: surface.width * .72; y2: surface.depth
                GradientStop { position: 0; color: MaterialTheme.rgba(surface.profile.upper, surface.stacked ? .2 : .05) }
                GradientStop { position: .32; color: MaterialTheme.rgba(surface.accent, surface.stacked ? .11 : .01) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathSvg {
                path: surface.stacked && !surface.shell
                    ? Geometry.frame(surface.bevel * 1.1, surface.bevel * 1.8,
                                     surface.width - surface.bevel * 3.5, surface.height - surface.bevel * 3.4,
                                     surface.radius * .84, surface.outline) : ""
            }
        }

        // Each chamfer receives its own color and bevel plane.
        ShapePath {
            strokeWidth: .7
            strokeColor: MaterialTheme.rgba(surface.profile.upper, surface.faceted ? .43 : 0)
            fillGradient: LinearGradient {
                x1: surface.width; y1: 0
                x2: surface.width * .70; y2: surface.depth
                GradientStop { position: 0; color: MaterialTheme.rgba(surface.profile.upper, .62 * surface.reflectivity) }
                GradientStop { position: .33; color: MaterialTheme.rgba(surface.profile.accent, .35 * surface.reflectivity) }
                GradientStop { position: .67; color: MaterialTheme.rgba(surface.profile.secondary, .31 * surface.reflectivity) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathSvg { path: surface.faceted && !surface.shell ? Geometry.facet(surface.width, surface.height, surface.radius, surface.outline, true) : "" }
        }

        ShapePath {
            strokeWidth: .8
            strokeColor: MaterialTheme.rgba(surface.profile.secondary, .18)
            fillGradient: LinearGradient {
                x1: 0; y1: surface.height
                x2: surface.width * .33; y2: surface.height * .68
                GradientStop { position: 0; color: MaterialTheme.rgba(surface.profile.secondary, .51 * surface.reflectivity) }
                GradientStop { position: .36; color: MaterialTheme.rgba(surface.profile.accent, .16 * surface.reflectivity) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathSvg { path: surface.faceted && !surface.shell ? Geometry.facet(surface.width, surface.height, surface.radius, surface.outline, false) : "" }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: surface.width; y2: surface.depth
                GradientStop { position: 0; color: MaterialTheme.rgba(surface.profile.upper, .58 * surface.reflectivity) }
                GradientStop { position: .35; color: MaterialTheme.rgba(surface.profile.accent, .20 * surface.reflectivity) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathSvg {
                path: surface.sculpted && !surface.recess && surface.width > 24 && surface.height > 12
                    ? `M ${surface.bevel * 1.4} ${surface.depth * .59} C ${surface.width * .12} ${surface.bevel * .30}
                       ${surface.width * .32} ${surface.bevel * .47} ${surface.width * .61} ${surface.bevel}
                       C ${surface.width * .39} ${surface.bevel * 1.16}
                       ${surface.width * .17} ${surface.depth * .42} ${surface.bevel * 1.4} ${surface.depth * .59} Z` : ""
            }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: surface.width; y2: surface.height
                GradientStop { position: 0; color: MaterialTheme.rgba(surface.accent, surface.emphasis * .39) }
                GradientStop { position: 1; color: MaterialTheme.rgba(surface.accent, surface.emphasis * .08) }
            }
            PathSvg { path: surface.emphasis > 0 ? surface.framePath : "" }
        }
    }

    Loader {
        active: surface.showReflection && surface.visible && surface.width > 280 && surface.height >= 30
            && GraphicsInfo.api !== GraphicsInfo.Software
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        height: Math.min(31, surface.height - 4)
        sourceComponent: Component {
            GlassReflection {
                tint: surface.profile.accent
                spectral: surface.profile.secondary
                polish: surface.profile.gloss
                faceted: surface.faceted
            }
        }
    }
}
