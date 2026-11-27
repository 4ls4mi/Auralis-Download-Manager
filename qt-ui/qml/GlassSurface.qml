pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import "MaterialGeometry.js" as Geometry

Item {
    id: surface
    clip: true

    property string material: MaterialTheme.current
    property string role: "content"
    property string fracturedEdge: ""
    property bool backdropAvailable: MaterialTheme.backdropAvailable
    property color accent: profile.accent
    property real emphasis: 0
    property color solidColor: profile.background
    property bool tintBacking: true
    property real mediaOverlay: -1
    property bool roundedPanel: false
    property real radius: roundedPanel && !shell ? Math.max(12, profile.radius)
        : studioPanel ? profile.panelRadius : profile.radius
    property bool showReflection: role === "toolbar" && profile.shape === "aero"

    readonly property var profile: MaterialTheme.profile(material)
    readonly property bool shell: role === "window" || role === "modal"
    readonly property bool recess: role === "content" || role === "field" || role === "sidebar"
    readonly property bool sculpted: ["bubble", "aero"].includes(profile.shape)
    readonly property bool stacked: ["smoke", "frost"].includes(profile.shape)
    readonly property bool faceted: ["prism", "ice", "chamfer"].includes(profile.shape)
    // Exact header/footer colors keep their contrast over any desktop, picture or video.
    readonly property bool customChrome: role === "title" ? Boolean(profile.titleOverride)
        : role === "footer" && Boolean(profile.footerOverride)
    readonly property bool classicTitle: role === "title" && Boolean(profile.mdm) && !customChrome
    readonly property color inactiveCaption: profile.mdm?.captionInactive || "transparent"
    readonly property bool useInactiveCaption: classicTitle && !Window.window?.active && inactiveCaption.a > 0
    readonly property color captionFace: useInactiveCaption ? inactiveCaption : flatFace
    readonly property string captionStyle: profile.mdmCaptionStyle || "system"
    readonly property bool shadedCaption: classicTitle && ["luna", "aero", "aqua"].includes(captionStyle)
    readonly property var captionStops: {
        if (!shadedCaption)
            return []
        const supplied = useInactiveCaption ? profile.mdm?.captionInactiveStops : profile.mdm?.captionStops
        if (supplied?.length >= 2)
            return supplied
        const bar = captionFace
        const gloss = profile.mdm?.gloss || profile.upper
        if (captionStyle === "aqua")
            return [{position: 0, color: MaterialTheme.mix(bar, gloss, .60, 1)}, {position: 1, color: bar}]
        const luna = captionStyle === "luna"
        return [
            {position: 0, color: MaterialTheme.mix(bar, gloss, .45, 1)},
            {position: luna ? .12 : .50, color: MaterialTheme.mix(bar, gloss, luna ? .12 : .20, 1)},
            {position: .50, color: bar},
            {position: 1, color: MaterialTheme.mix(bar, luna ? "#000000" : gloss, .10, 1)}
        ]
    }
    readonly property bool flatStudio: profile.cleanStudio === true || customChrome
    readonly property bool studioPanel: profile.panelRadius !== undefined
        && ["card", "summary", "connections"].includes(role)
    readonly property bool cleanChrome: profile.opaque || profile.softChrome === true
    readonly property bool reflectionPlane: faceted && (!cleanChrome || shell || role === "toolbar")
    readonly property string outline: shell ? "square" : roundedPanel || profile.softChrome ? "round" : profile.shape
    readonly property color flatFace: (role === "summary" ? profile.summaryFill : profile.roleFaces?.[role])
        || profile.background
    readonly property bool customLayer: role === "sidebar" ? Boolean(profile.sidebarOverride)
        : Boolean(profile.contentOverride) && ["content", "card", "field", "summary", "connections"].includes(role)
    readonly property color fractureInk: role === "title" ? profile.titleInk || profile.ink
        : role === "sidebar" ? profile.sidebarInk || profile.ink
        : role === "footer" ? profile.footerInk || profile.ink : profile.ink
    readonly property color fractureMuted: role === "title" ? profile.titleMuted || profile.muted
        : role === "sidebar" ? profile.sidebarMuted || profile.muted
        : role === "footer" ? profile.footerMuted || profile.muted : profile.muted
    readonly property bool plainMaterialAlpha: backdropAvailable && profile.opaque && MaterialTheme.translucency > 0
    readonly property real foregroundBacking: role === "field" ? .94 : role === "sidebar" ? .88 : .78
    readonly property real flatFaceOpacity: backdropAvailable && MaterialTheme.translucency >= 0
        ? Math.max(foregroundBacking, MaterialTheme.opacityFor(material)) : 1
    readonly property real bevel: Math.max(1, Math.min(profile.bevel, height * .14, width * .10))
    readonly property real depth: Math.min(height / 3, 28 + profile.bevel)
    readonly property real reflectivity: profile.gloss * (role === "field" ? .54 : 1)
    readonly property real backingAlpha: {
        const amount = MaterialTheme.opacityFor(material);
        if (shell)
            return mediaOverlay >= 0 ? mediaOverlay : backdropAvailable ? amount : 1;
        if (plainMaterialAlpha)
            return Math.max(foregroundBacking, amount);
        if (role === "field")
            return Math.min(.82, .18 + amount * .72);
        return amount * (recess ? .32 : role === "toolbar" || role === "footer" ? .65 : .45);
    }
    readonly property color backing: {
        if (shell) {
            if (!backdropAvailable)
                return solidColor;
            return tintBacking ? MaterialTheme.tint(solidColor, backingAlpha) : MaterialTheme.rgba(solidColor, backingAlpha);
        }
        if (customLayer)
            return MaterialTheme.rgba(flatFace, flatFaceOpacity);
        return MaterialTheme.tint(profile.background, backingAlpha);
    }
    readonly property color rim: MaterialTheme.rgba(profile.edge, .33 + .32 * reflectivity)
    readonly property string framePath: Geometry.frame(.6, .6, width - 1.2, height - 1.2, radius, outline)

    Rectangle {
        anchors.fill: parent
        visible: !surface.fracturedEdge && surface.flatStudio
        radius: surface.profile.mdm ? surface.role === "field" ? surface.profile.radius : 0
            : !surface.shell && (surface.roundedPanel || surface.role === "field" || surface.studioPanel)
                ? surface.radius : 0
        color: surface.classicTitle ? surface.captionFace
            : surface.customChrome || surface.profile.mdm ? surface.flatFace
            : surface.shell ? surface.backing : MaterialTheme.rgba(surface.flatFace, surface.flatFaceOpacity)
        gradient: surface.shadedCaption ? classicCaptionGradient : null
        Gradient {
            id: classicCaptionGradient
            GradientStop { position: surface.captionStops[0]?.position ?? 0; color: surface.captionStops[0]?.color || surface.captionFace }
            GradientStop { position: surface.captionStops[1]?.position ?? 1; color: surface.captionStops[1]?.color || surface.captionFace }
            GradientStop { position: surface.captionStops[2]?.position ?? 1; color: surface.captionStops[2]?.color || surface.captionFace }
            GradientStop { position: surface.captionStops[3]?.position ?? 1; color: surface.captionStops[3]?.color || surface.captionFace }
        }
        border.width: surface.shell || surface.roundedPanel || surface.role === "field" ? 1 : 0
        border.color: surface.profile.surfaceLine || surface.profile.divider

        Rectangle {
            width: parent.width
            height: 1
            y: surface.role === "footer" ? 0 : parent.height - height
            visible: !surface.roundedPanel && ["title", "toolbar", "footer"].includes(surface.role)
            color: surface.profile.surfaceLine || surface.profile.divider
        }
    }

    Shape {
        anchors.fill: parent
        visible: !surface.fracturedEdge && !surface.flatStudio
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: surface.shell ? 1 : 1.15
            strokeColor: surface.rim
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
                GradientStop {
                    position: 0
                    color: MaterialTheme.rgba(surface.recess ? surface.profile.shade : surface.profile.upper,
                        surface.recess ? .24 : .12 + .27 * surface.reflectivity)
                }
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
                path: surface.cleanChrome && !surface.shell ? "" :
                    Geometry.frame(surface.bevel, surface.bevel, surface.width - 2 * surface.bevel,
                                   surface.height - 2 * surface.bevel, Math.max(0, surface.radius - surface.bevel), surface.outline)
            }
        }

        ShapePath {
            strokeWidth: Math.max(.6, surface.bevel * .28)
            strokeColor: MaterialTheme.rgba(surface.profile.secondary, .15 + surface.reflectivity * .22)
            fillColor: "transparent"
            PathSvg {
                path: surface.cleanChrome ? "" : Geometry.frame(surface.bevel + 1.7, surface.bevel + 1.7,
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
            PathSvg { path: surface.reflectionPlane ? Geometry.facet(surface.width, surface.height, surface.radius, surface.outline, true) : "" }
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
            PathSvg { path: surface.reflectionPlane ? Geometry.facet(surface.width, surface.height, surface.radius, surface.outline, false) : "" }
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
                GradientStop { position: 1; color: MaterialTheme.rgba(surface.accent, surface.emphasis * .07) }
            }
            PathSvg { path: surface.emphasis > 0 ? surface.framePath : "" }
        }
    }

    Loader {
        anchors.fill: parent
        active: Boolean(surface.fracturedEdge)
        sourceComponent: FracturedPanel {
            edge: surface.fracturedEdge
            face: surface.flatFace
            ink: surface.fractureInk
            mutedInk: surface.fractureMuted
            forceOpaque: surface.customChrome || surface.customLayer || Boolean(surface.profile.textOverride)
            requestedOpacity: MaterialTheme.opacityFor(surface.material)
            cornerRadius: Math.max(2, Math.min(12, WindowAppearance.cornerRadius * .48))
        }
    }

    Loader {
        active: !surface.fracturedEdge && surface.showReflection && surface.visible && surface.width > 280 && surface.height >= 30
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
