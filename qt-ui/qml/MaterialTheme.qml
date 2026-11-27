pragma Singleton

import QtQuick

QtObject {
    id: theme

    readonly property string defaultMaterial: "mdm-classic"
    property string current: defaultMaterial
    property string mdmMode: "system"
    property var mdmPresets: ({})
    readonly property bool mdmAppearance: isMdmPreset(current)
    readonly property bool mdmDark: mdmMode === "dark" || (mdmMode === "system"
        && (Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
            || (Qt.styleHints.colorScheme === Qt.ColorScheme.Unknown && systemColors.window.hsvValue < .5)))
    readonly property var mdmPresetNames: ({
        "mdm-classic": qsTr("Classic Desktop"),
        "mdm-native": qsTr("System Accent"),
        "mdm-high-contrast": qsTr("High Contrast"),
        "mdm-metro": qsTr("Flat Metro"),
        "mdm-adwaita": qsTr("Adwaita"),
        "mdm-breeze": qsTr("Breeze"),
        "mdm-luna": qsTr("Luna Blue"),
        "mdm-aero": qsTr("Aero Glass"),
        "mdm-aqua": qsTr("Aqua Gel"),
        "mdm-emerald": qsTr("Emerald Fluent")
    })
    readonly property var mdmPresetIds: Object.keys(mdmPresetNames)

    property SystemPalette systemColors: SystemPalette {
        colorGroup: SystemPalette.Active
        onHighlightChanged: Qt.callLater(theme.loadMdmPresets)
    }

    Component.onCompleted: Qt.callLater(loadMdmPresets)

    function loadMdmPresets() {
        if (typeof engine === "undefined" || typeof engine.request !== "function")
            return;
        engine.request({shellAction: "appearance-presets", systemAccent: String(systemColors.highlight)},
            (presets, error) => {
                if (!error && presets?.["mdm-classic"])
                    mdmPresets = presets;
            });
    }

    function isMdmPreset(id) {
        return mdmPresetIds.includes(id);
    }

    function hasMaterial(id) {
        return isMdmPreset(id) || Object.prototype.hasOwnProperty.call(builtins, id)
            || Object.prototype.hasOwnProperty.call(userMaterials, id);
    }

    function mdmProfile(id) {
        const selected = mdmPresets[id];
        const color = mdmDark ? selected?.dark : selected?.light;
        if (!color)
            return null;
        return preset({
            name: mdmPresetNames[id] || selected.name, mdm: color, mdmProgress: selected.progress,
            mdmIconSet: selected.iconSet || "", mdmIconStyle: selected.iconStyle || "color",
            mdmCaptionStyle: selected.captionStyle || "system",
            mdmListRow: selected.listRow, mdmListHeader: selected.listHeader,
            titleInk: color.captionText || color.text, titleMuted: color.captionInactiveText || color.muted,
            finish: "matte", shape: "round", opaque: true, cleanStudio: true, light: color.light,
            radius: selected.radius, panelRadius: 0, buttonRadius: selected.buttonRadius,
            mdmGlossyButtons: selected.glossyButtons,
            translucency: 0, gloss: 0, bevel: 0,
            background: color.background, ink: color.text, text: color.text, muted: color.muted,
            edge: color.buttonBorder, shade: color.background, upper: color.gloss, accent: color.accent,
            secondary: color.accent, divider: color.divider, surfaceLine: color.divider,
            positive: color.positive, caution: color.warning, destructive: color.error,
            buttonFace: color.button, rowSelectionFill: color.selection, rowSelectionInk: color.selectionText,
            sidebarInk: color.text, sidebarMuted: color.muted, navigationInk: color.text,
            navigationFill: color.tree, railFill: color.tree,
            menuSurface: color.menu, menuHighlight: color.menuHot, menuRail: color.menuBorder,
            roleFaces: {title: color.caption, field: color.field, sidebar: color.tree, content: color.list,
                toolbar: color.background, footer: color.background, card: color.background,
                connections: color.background, summary: color.background}
        });
    }
    readonly property bool wideSweepEnabled: current === "violet-rail-wide-sweep"
    property real translucency: -1
    property color tintColor: "#7298bc"
    property real tintStrength: 0
    property bool backdropAvailable: false
    property bool reducedMotion: false
    property var userMaterials: ({})
    property var materialCustomizations: ({})
    property var colorTheme: null
    property string forcedAccent: ""
    property string progressPalette: "material"
    property string connectionPalette: "material"
    property string graphPalette: "material"
    property int visibleButtonLights: 0
    property real buttonLightPhase: 0

    property Timer buttonLightClock: Timer {
        interval: 40
        repeat: true
        triggeredOnStart: true
        running: theme.visibleButtonLights > 0 && !theme.reducedMotion
        onTriggered: theme.buttonLightPhase = (Date.now() % 5200) / 5200 * Math.PI * 2
    }

    readonly property var buttonFinishes: ({
        matte: {idle: .25, hover: .77, press: .49, selected: .66, tint: .10, opacity: .92,
            lip: .77, crown: .15, shoulder: .29, depth: .14, light: .14, spread: .76, slant: .10},
        satin: {idle: .27, hover: .70, press: .47, selected: .61, tint: .13, opacity: .92,
            lip: .94, crown: .32, shoulder: .40, depth: .20, light: .18, spread: .49, slant: .73},
        gloss: {idle: .35, hover: .89, press: .56, selected: .74, tint: .16, opacity: .76,
            lip: 1.24, crown: .42, shoulder: .32, depth: .32, light: .26, spread: .29, slant: 1.00},
        frosted: {idle: .29, hover: .76, press: .51, selected: .65, tint: .23, opacity: .83,
            lip: 1.08, crown: .34, shoulder: .46, depth: .20, light: .21, spread: .66, slant: .27},
        clear: {idle: .31, hover: .82, press: .53, selected: .69, tint: .20, opacity: .70,
            lip: 1.11, crown: .24, shoulder: .26, depth: .28, light: .24, spread: .42, slant: .87}
    })

    readonly property var indicatorPalettes: ({
        "blue-purple": { label: qsTr("Blue / Purple"), colors: ["#13bafa", "#9f57f8"] },
        ocean: { label: qsTr("Ocean"), colors: ["#05a9fa", "#44f3bd"] },
        sunset: { label: qsTr("Sunset"), colors: ["#ffb534", "#f747c8"] },
        aurora: { label: qsTr("Aurora"), colors: ["#36efb7", "#be69ff"] },
        silver: { label: qsTr("Silver"), colors: ["#a1b7d4", "#f9fcff"] },
        cobalt: { label: qsTr("Solid cobalt"), colors: ["#347dff", "#347dff"] },
        emerald: { label: qsTr("Solid emerald"), colors: ["#14cf8c", "#14cf8c"] },
        tangerine: { label: qsTr("Solid orange"), colors: ["#ff8c21", "#ff8c21"] },
        coral: { label: qsTr("Solid coral"), colors: ["#ff566c", "#ff566c"] },
        violet: { label: qsTr("Solid violet"), colors: ["#ad6bff", "#ad6bff"] },
        lime: { label: qsTr("Solid lime"), colors: ["#b9ed34", "#b9ed34"] },
        candy: { label: qsTr("Candy"), colors: ["#ff63a8", "#ffe36c"] },
        arctic: { label: qsTr("Arctic"), colors: ["#a4ffff", "#cfb5ff"] },
        fire: { label: qsTr("Fire"), colors: ["#ffdb32", "#fa3652"] },
        forest: { label: qsTr("Forest"), colors: ["#aef244", "#049c91"] },
        "jade-brass": { label: qsTr("Jade & Brass"), colors: ["#087c72", "#e0ae58"] },
        "cherry-cola": { label: qsTr("Cherry Cola"), colors: ["#a9194c", "#ff7376"] },
        "pearl-opal": { label: qsTr("Pearl Opal"), colors: ["#a8b3e8", "#ffe2da"] },
        "copper-sky": { label: qsTr("Copper Sky"), colors: ["#e46b39", "#6dd9fb"] },
        "electric-lime": { label: qsTr("Electric Lime"), colors: ["#6357ff", "#c7fa43"] },
        "blue-steel": { label: qsTr("Blue Steel"), colors: ["#527aa6", "#a1cbd6"] },
        "grape-taffy": { label: qsTr("Grape Taffy"), colors: ["#863de2", "#ffa6db"] },
        watermelon: { label: qsTr("Watermelon"), colors: ["#ff5271", "#70edaa"] }
    })
    readonly property var indicatorChoices: [{ value: "material", label: qsTr("Use material colors") }]
        .concat(Object.keys(indicatorPalettes).map(id => ({ value: id, label: indicatorPalettes[id].label })))
    readonly property string effectiveProgressPalette: resolvedPalette(progressPalette, "blue-purple", "progress")
    readonly property string effectiveConnectionPalette: resolvedPalette(connectionPalette, "ocean", "connections")
    readonly property string effectiveGraphPalette: resolvedPalette(graphPalette, "blue-purple", "graph")
    readonly property var progressColors: colorsFor(progressPalette, effectiveProgressPalette, "progress")
    readonly property var connectionColors: colorsFor(connectionPalette, effectiveConnectionPalette, "connections")
    readonly property var graphColors: colorsFor(graphPalette, effectiveGraphPalette, "graph")

    readonly property var violetRailPreset: preset({
        name: qsTr("Violet Rail"), finish: "matte", shape: "round", opaque: true, cleanStudio: true,
        layout: "violetRail", background: "#242634", edge: "#674f92", shade: "#1c1d2a", upper: "#e7dcff",
        accent: "#a379ff", secondary: "#8558ff", ink: "#f6f3ff", muted: "#c3bfd6",
        divider: "#4c485e", positive: "#4ce6a2", caution: "#ffba52", destructive: "#ff577f",
        buttonFace: "#352751", buttonChroma: .13, surfaceLine: "#403e53", railFill: "#542da1",
        sidebarInk: "#f3efff", sidebarMuted: "#c4b6e4",
        navigationFill: "#54309a", navigationInk: "#fff7ff", rowSelectionFill: "#38334e",
        rowSelectionInk: "#fbf7ff", summaryFill: "#422f68", summaryInk: "#f7efff",
        menuSurface: "#28253a", menuHighlight: "#7744db", menuRail: "#bc94ff",
        translucency: 0, gloss: .15, radius: 8, bevel: 1.4, panelRadius: 8,
        indicatorDefaults: {
            progress: {palette: "violet", colors: ["#9069f8", "#ba98ff"]},
            connections: {palette: "aurora", colors: ["#8c79fb", "#7ce8d0"]},
            graph: {palette: "violet", colors: ["#9468ec", "#c7a7ff"]}
        },
        roleFaces: {title: "#272538", toolbar: "#272838", sidebar: "#2a2939", content: "#262837",
                    footer: "#242633", field: "#212331", card: "#222534", connections: "#222534"}
    })

    readonly property var builtins: ({
        "mint-transfer-deck": preset({
            name: qsTr("Mint Transfer Deck"), finish: "frosted", shape: "round", cleanStudio: true,
            frostedStudio: true, layout: "mintDeck", light: true,
            background: "#d8f0e9", edge: "#fcfffe", shade: "#498477", upper: "#ffffff",
            accent: "#007d58", secondary: "#329c85", ink: "#17352d", text: "#17352d", muted: "#365e53",
            divider: "#99c5b8", positive: "#087a57", caution: "#855213", destructive: "#a62b51",
            buttonFace: "#e4f3ee", sidebarInk: "#173b32", sidebarMuted: "#355b50",
            navigationFill: "#007c58", navigationInk: "#f2fff9", rowSelectionFill: "#bde6d9",
            rowSelectionInk: "#163d32", summaryFill: "#08634f", summaryInk: "#f1fff9",
            menuSurface: "#f0faf6", menuHighlight: "#00805d", menuRail: "#58ba9d",
            translucency: .62, gloss: .77, radius: 15, bevel: 3.4, panelRadius: 14,
            indicatorDefaults: {
                progress: {palette: "emerald", colors: ["#229e80", "#68dbc2"]},
                connections: {palette: "emerald", colors: ["#29ad8c", "#91e5cc"]},
                graph: {palette: "emerald", colors: ["#74e4ba", "#bcf8de"]}
            },
            roleFaces: {title: "#edf8f4", toolbar: "#edf8f4", sidebar: "#edf9f4", content: "#f5fbf8",
                        footer: "#dbeee6", field: "#e9f5ef", card: "#e6f3ed", connections: "#e3f3ed"}
        }),
        "dark-studio": preset({
            name: qsTr("Dark Studio"), finish: "frosted", shape: "round", cleanStudio: true,
            frostedStudio: true, layout: "darkStudio",
            background: "#242c3c", edge: "#a0b2cd", shade: "#0e1727", upper: "#e8f3ff",
            accent: "#ff958c", secondary: "#83d9c9", ink: "#f1f5ff", muted: "#c5cfe3",
            divider: "#54647b", positive: "#8ee0c9", caution: "#ffd192", destructive: "#ff8b9b",
            buttonFace: "#333e53", sidebarInk: "#242c3c", sidebarMuted: "#364357",
            navigationFill: "#e5edf9", navigationInk: "#202d40", rowSelectionFill: "#3c4c67",
            rowSelectionInk: "#f9fbff", summaryFill: "#35425a", summaryInk: "#f1f5ff",
            menuSurface: "#273345", menuHighlight: "#ff958c", menuRail: "#83d9c9",
            translucency: .65, gloss: .76, radius: 17, bevel: 3.4, panelRadius: 12,
            indicatorDefaults: {
                progress: {palette: "coral", colors: ["#f88e86", "#ffc4b6"]},
                connections: {palette: "emerald", colors: ["#73cfbd", "#acf0de"]},
                graph: {palette: "jade-brass", colors: ["#7addce", "#adccfb"]}
            },
            roleFaces: {title: "#303c52", toolbar: "#293448", sidebar: "#cbd6e6", content: "#252e41",
                        footer: "#263144", field: "#29364b", card: "#354159", connections: "#2b4652"}
        }),
        "fog-slate": preset({
            name: qsTr("Fog Slate"), finish: "matte", shape: "round", opaque: true, cleanStudio: true,
            layout: "fogSlate", background: "#2a2f3b", edge: "#555b6a", shade: "#1e222c", upper: "#e1e6ef",
            accent: "#ff8791", secondary: "#76dabd", ink: "#f5f6fa", muted: "#bec5d2",
            divider: "#495164", positive: "#79ddbe", caution: "#ffd38c", destructive: "#ff8992",
            buttonFace: "#323949", surfaceLine: "#434b5b", sidebarInk: "#252e3d", sidebarMuted: "#4e596a",
            navigationFill: "#ff8791", navigationInk: "#291c27", rowSelectionFill: "#323b4c",
            rowSelectionInk: "#f9fafc", summaryFill: "#254b4a", summaryInk: "#e6fff6",
            menuSurface: "#242934", menuHighlight: "#ff8791", menuRail: "#6ce0c2",
            translucency: 0, gloss: .14, radius: 6, bevel: 1.4, panelRadius: 6,
            indicatorDefaults: {
                progress: {palette: "coral", colors: ["#ff7988", "#ff9c9f"]},
                connections: {palette: "emerald", colors: ["#52d7b1", "#9af2d4"]},
                graph: {palette: "emerald", colors: ["#54cdb0", "#98e7d0"]}
            },
            roleFaces: {title: "#242936", toolbar: "#2a303e", sidebar: "#dbe0e7", content: "#2b303e",
                        footer: "#252b38", field: "#222834", card: "#252c39", connections: "#252c39"}
        }),
        "violet-rail": violetRailPreset,
        "violet-rail-wide-sweep": Object.assign({}, violetRailPreset, {
            name: qsTr("Violet Rail Wide Sweep")
        }),
        "coral-slate": preset({
            name: qsTr("Coral Slate"), finish: "matte", shape: "round", opaque: true, cleanStudio: true,
            layout: "coralSlate", background: "#303344", edge: "#52566b", shade: "#222532", upper: "#e8eaf5",
            accent: "#ff848b", secondary: "#a581f7", ink: "#f6f6fb", muted: "#c4c8db",
            divider: "#494e64", positive: "#83e2bd", caution: "#ffd087", destructive: "#ff858d",
            buttonFace: "#393d50", surfaceLine: "#43475a", sidebarInk: "#f3f2fb", sidebarMuted: "#c2c5d7",
            navigationFill: "#ff848b", navigationInk: "#271e29", rowSelectionFill: "#252836",
            rowSelectionInk: "#f9f7fd", summaryFill: "#604fa2", summaryInk: "#fbf7ff",
            menuSurface: "#282c3b", menuHighlight: "#6652a4", menuRail: "#c1a0ff",
            translucency: 0, gloss: .14, radius: 10, bevel: 1.4, panelRadius: 12,
            indicatorDefaults: {
                progress: {palette: "coral", colors: ["#ff8290", "#b089fa"]},
                connections: {palette: "aurora", colors: ["#ff8392", "#ac84fa"]},
                graph: {palette: "violet", colors: ["#a478f5", "#be98ff"]}
            },
            roleFaces: {title: "#2d3141", toolbar: "#303344", sidebar: "#303344", content: "#303344",
                        footer: "#2d3141", field: "#272b3b", card: "#252837", connections: "#252837"}
        }),
        "black-ceramic": preset({
            name: qsTr("Black Ceramic"), finish: "matte", shape: "round", opaque: true, cleanStudio: true,
            background: "#161312", edge: "#3d302a", shade: "#0d0b0b", upper: "#e4c4b4",
            accent: "#ff8056", secondary: "#ffab87", ink: "#fff6f1", muted: "#cec0bb",
            divider: "#6d5650", positive: "#ff9870", caution: "#ffd080", destructive: "#ff817b",
            buttonFace: "#241b18", surfaceLine: "#45332e",
            navigationFill: "#3d241d", navigationInk: "#ffac8c",
            menuSurface: "#201816", menuHighlight: "#ff754d", menuRail: "#ffd4a5",
            translucency: 0, gloss: .19, radius: 8, bevel: 1.8,
            indicatorPalette: "tangerine", liquidColors: ["#ff512d", "#ffca7f"],
            roleFaces: {title: "#191413", toolbar: "#191514", sidebar: "#1c1615",
                        content: "#171312", footer: "#1b1514", field: "#251b18", card: "#211917"}
        }),
        "monochrome-studio": preset({
            name: qsTr("Monochrome Studio"), finish: "satin", shape: "round", opaque: true,
            light: true, cleanStudio: true,
            background: "#fefefe", edge: "#d9d4df", shade: "#c4b9ce", upper: "#ffffff",
            accent: "#6024cf", secondary: "#007b54", ink: "#18141e", muted: "#554e5a",
            divider: "#a29ba9", positive: "#067350", caution: "#975410", destructive: "#a82d52",
            buttonFace: "#f1edf5", surfaceLine: "#e1dce5",
            navigationFill: "#eee7fb", navigationInk: "#551dbb",
            menuSurface: "#ffffff", menuHighlight: "#641bde", menuRail: "#b897ff",
            translucency: 0, gloss: .23, radius: 9, bevel: 2,
            indicatorPalette: "emerald", liquidColors: ["#18dd8c", "#69ffba"],
            roleFaces: {title: "#ffffff", toolbar: "#fbfafc", sidebar: "#f8f7fa",
                        content: "#ffffff", footer: "#f9f7fb", field: "#f6f3f8", card: "#f7f5f9"}
        }),
        carbon: preset({
            name: qsTr("Carbon"), finish: "matte", shape: "round", opaque: true,
            background: "#171c24", edge: "#73859f", accent: "#6bdcff", secondary: "#bb93ff",
            shade: "#05080e", upper: "#baccdf", translucency: 0, gloss: .31, radius: 8, bevel: 2,
            buttonFace: "#283344", positive: "#54ee9b", caution: "#ffc15a", destructive: "#ff718d"
        }),
        porcelain: preset({
            name: qsTr("Porcelain"), finish: "satin", shape: "round", opaque: true, light: true,
            background: "#edf2fc", edge: "#aabde2", accent: "#0768b8", secondary: "#6742cb",
            shade: "#738ab5", upper: "#ffffff", translucency: 0, gloss: .44, radius: 10, bevel: 3,
            buttonFace: "#fafbff", positive: "#087c4f", caution: "#995307", destructive: "#c03758"
        }),
        "prismatic-glass": preset({
            name: qsTr("Prism Glass"), finish: "gloss", shape: "prism", softChrome: true,
            background: "#173562", edge: "#76caff", accent: "#56e1ff", secondary: "#c18cff",
            shade: "#0a173c", upper: "#e9f8ff", translucency: .68, gloss: .96, radius: 9, bevel: 4,
            buttonFace: "#254a7b", positive: "#55f0ad", caution: "#ffcf64", destructive: "#ff7799"
        }),
        "builtin-aurora-night": preset({
            name: qsTr("Aurora Glass — Dark"), finish: "frosted", shape: "chamfer",
            background: "#171a40", edge: "#a4c8ff", accent: "#66ddff", secondary: "#bf93ff",
            shade: "#05091f", upper: "#d2e0ff", translucency: 0.72, gloss: 0.72, radius: 14, bevel: 4
        }),
        "builtin-aurora-ice": preset({
            name: qsTr("Aurora Glass — Light"), finish: "frosted", shape: "ice", light: true,
            background: "#cfeaff", edge: "#f2feff", accent: "#005c98", secondary: "#5d39ad",
            shade: "#2a638e", upper: "#fcffff", translucency: 0.78, gloss: 0.86, radius: 11, bevel: 5
        }),
        "water-bubble": preset({
            name: qsTr("Water Bubble"), finish: "gloss", shape: "bubble",
            background: "#132b55", edge: "#a3e4ff", accent: "#56eeff", secondary: "#eaa0ff",
            shade: "#090e31", upper: "#ecfcff", translucency: 0.78, gloss: 0.95, radius: 22, bevel: 7
        }),
        "ice-edge": preset({
            name: qsTr("Ice Edge"), finish: "clear", shape: "ice", light: true,
            background: "#c7dfee", edge: "#f4ffff", accent: "#045f99", secondary: "#453bb9",
            shade: "#37506e", upper: "#f6ffff", translucency: 0.7, gloss: 0.78, radius: 14, bevel: 5
        }),
        "smoked-crystal": preset({
            name: qsTr("Smoked Crystal"), finish: "satin", shape: "smoke",
            background: "#241b29", edge: "#d6a791", accent: "#fad19f", secondary: "#c794eb",
            shade: "#120b18", upper: "#fde4c4", translucency: 0.7, gloss: 0.44, radius: 10, bevel: 4
        }),
        "frosted-water-351": preset({
            name: qsTr("Frosted Layers"), finish: "frosted", shape: "frost",
            background: "#193956", edge: "#b5edfa", accent: "#7ce7fa", secondary: "#cab4ff",
            shade: "#102543", upper: "#e3fcff", translucency: 0.57, gloss: 0.66, radius: 18, bevel: 5
        }),
        "aero-gloss": preset({
            name: qsTr("Aero Gloss"), finish: "gloss", shape: "aero",
            background: "#163044", edge: "#c0f5ff", accent: "#69d4ff", secondary: "#69ffca",
            shade: "#07182b", upper: "#f2ffff", translucency: 0.7, gloss: 0.9, radius: 14, bevel: 5
        }),
        "brushed-glass": preset({
            name: qsTr("Brushed Glass"), finish: "satin", shape: "chamfer",
            background: "#14383f", edge: "#9dd9d3", accent: "#6cf6d2", secondary: "#abdefc",
            shade: "#0b2429", upper: "#c9eeea", translucency: 0.74, gloss: 0.51, radius: 5, bevel: 3
        }),
        "rose-pine": preset({
            name: qsTr("Rose Pine"), finish: "matte", shape: "aero",
            background: "#3f243e", edge: "#e7bad1", accent: "#ff9bd2", secondary: "#ebba96",
            shade: "#2b1127", upper: "#ffe0e6", translucency: 0.64, gloss: 0.41, radius: 16, bevel: 4
        }),
        "oversimplified": preset({
            name: qsTr("Oversimplified & Accentuated"), finish: "matte", shape: "plain",
            background: "#171b3d", edge: "#9290c8", accent: "#9ba7ff", secondary: "#91dfc8",
            shade: "#12152d", upper: "#d4d5ff", translucency: 0.83, gloss: 0.23, radius: 3, bevel: 2
        }),
        "builtin-obsidian-matte": preset({
            name: qsTr("Matte Obsidian"), finish: "matte", shape: "chamfer",
            background: "#2c251d", edge: "#d2ae80", accent: "#ffcb73", secondary: "#f29f64",
            shade: "#141015", upper: "#ffdea6", translucency: 0.52, gloss: 0.27, radius: 5, bevel: 3
        }),
        "builtin-smoked-glass": preset({
            name: qsTr("Smoked Glass"), finish: "clear", shape: "smoke",
            background: "#372a25", edge: "#edc193", accent: "#ffbd7b", secondary: "#c7a787",
            shade: "#201720", upper: "#ffdfb4", translucency: 0.67, gloss: 0.52, radius: 12, bevel: 4
        }),
        "builtin-black-glass": preset({
            name: qsTr("Black Blur Glass"), finish: "clear", shape: "round",
            background: "#11141e", edge: "#b6c0d1", accent: "#a9caff", secondary: "#92b4dc",
            shade: "#06070c", upper: "#e1ebf4", translucency: 0.8, gloss: 0.48, radius: 9, bevel: 3
        }),
        "builtin-pearl-frost": preset({
            name: qsTr("Pearl Frost"), finish: "frosted", shape: "frost", light: true,
            background: "#f6edf4", edge: "#fbf4ff", accent: "#75328f", secondary: "#27687c",
            shade: "#6d537b", upper: "#fff8ed", translucency: 0.6, gloss: 0.66, radius: 18, bevel: 5
        }),
        "window-glass": preset({
            name: qsTr("Window Glass"), finish: "clear", shape: "chamfer",
            background: "#192b44", edge: "#b4d3f1", accent: "#85d5ff", secondary: "#9abaff",
            shade: "#0c1930", upper: "#e3f4ff", translucency: 0.65, gloss: 0.5, radius: 8, bevel: 3
        })
    })

    readonly property var palette: profile(current)
    readonly property var menuColors: menuPalette(palette)
    readonly property var materials: Object.keys(builtins)
        .filter(id => id !== "window-glass")
        .concat(Object.keys(userMaterials), mdmPresetIds.filter(id => Boolean(mdmPresets[id])))
        .map(id => ({ id: id, name: profile(id).name }))

    function preset(options) {
        const light = options.light === true;
        const angular = ["chamfer", "prism", "ice"].includes(options.shape);
        return Object.assign({
            light: light,
            opaque: false,
            text: light ? "#152b43" : "#f3f9ff",
            ink: light ? "#152b43" : "#f3f9ff",
            muted: light ? "#394c66" : "#c1d3e9",
            divider: light ? "#617f9d" : "#79a3ca",
            positive: light ? "#0c6545" : "#72efbb",
            caution: light ? "#815013" : "#ffd18a",
            destructive: light ? "#923554" : "#ff9dbd",
            controls: angular ? "angular" : options.shape === "bubble" || options.shape === "aero" ? "soft" : "rounded"
        }, options);
    }

    function profile(id) {
        const mdm = mdmProfile(id);
        if (mdm)
            return applyMaterialColors(mdm, id);
        let result = Object.prototype.hasOwnProperty.call(builtins, id) ? builtins[id] : builtins.carbon;
        const stored = Object.prototype.hasOwnProperty.call(userMaterials, id) ? userMaterials[id] : null;
        if (stored) {
            const byFinish = {
                matte: "builtin-obsidian-matte", satin: "brushed-glass", gloss: "aero-gloss",
                frosted: "frosted-water-351", clear: "window-glass"
            };
            const base = builtins[byFinish[stored.finish]];
            result = Object.assign({}, base, {
                name: stored.name,
                finish: stored.finish,
                controls: stored.controls,
                shape: stored.controls === "angular" ? "chamfer" : stored.controls === "soft" ? "aero" : "round",
                radius: stored.controls === "angular" ? 5 : stored.controls === "soft" ? 16 : 9,
                translucency: stored.translucency / 100,
                gloss: stored.shading / 100,
                layout: stored.layout,
                textStyle: stored.text
            });
        }
        if (!colorTheme)
            return applyMaterialColors(withAccent(result), id);

        const light = colorTheme.light === true;
        const contrast = preset({ light: light, shape: result.shape });
        const rgb = colorTheme.surface;
        const surface = rgb && rgb.length === 3
            ? Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1) : light ? "#e8f1fa" : "#172135";
        const ground = rgba(surface, 1);
        const tone = rgba(colorTheme.accent, 1);
        return applyMaterialColors(withAccent(Object.assign({}, result, {
            light: light, text: contrast.text, ink: contrast.ink, muted: contrast.muted,
            divider: contrast.divider, positive: contrast.positive, caution: contrast.caution,
            destructive: contrast.destructive, accent: colorTheme.accent, secondary: colorTheme.secondary,
            roleFaces: undefined, surfaceLine: contrast.divider, buttonFace: undefined,
            navigationFill: undefined, navigationInk: undefined, menuSurface: undefined,
            menuHighlight: undefined, menuRail: undefined, sidebarInk: undefined, sidebarMuted: undefined,
            rowSelectionFill: undefined, rowSelectionInk: undefined, summaryFill: undefined, summaryInk: undefined,
            background: Qt.rgba(ground.r * .78 + tone.r * .22, ground.g * .78 + tone.g * .22,
                                ground.b * .78 + tone.b * .22, 1)
        })), id);
    }

    function applyMaterialColors(base, id) {
        const custom = materialCustomizations[id];
        if (!custom || !(custom.sidebar || custom.content || custom.menu || custom.text || custom.header || custom.footer))
            return base;

        const layers = Object.assign({}, base.roleFaces);
        const adjusted = {roleFaces: layers, textOverride: custom.text || ""};
        const text = custom.text || base.ink;
        const muted = custom.text || base.muted;
        if (custom.sidebar) {
            layers.sidebar = custom.sidebar;
            adjusted.railFill = custom.sidebar;
            adjusted.sidebarOverride = custom.sidebar;
        }
        if (custom.content) {
            const ink = controlTextInk(text, custom.content);
            const edge = relativeLuminance(ink) < relativeLuminance(custom.content) ? "#ffffff" : "#000000";
            layers.content = custom.content;
            layers.card = mix(custom.content, edge, .05, 1);
            layers.field = mix(custom.content, edge, .09, 1);
            layers.summary = layers.card;
            layers.connections = layers.card;
            adjusted.summaryFill = layers.summary;
            adjusted.contentOverride = custom.content;
        }
        if (custom.header) {
            layers.title = custom.header;
            adjusted.titleOverride = custom.header;
        }
        if (custom.footer) {
            layers.footer = custom.footer;
            adjusted.footerOverride = custom.footer;
        }
        if (custom.menu) {
            adjusted.menuSurface = custom.menu;
            adjusted.menuOverride = custom.menu;
        }

        if (custom.sidebar || custom.text) {
            const sidebar = custom.sidebar || (id === "violet-rail-wide-sweep" && base.railFill)
                || layers.sidebar || base.background;
            adjusted.sidebarInk = controlTextInk(custom.text || base.sidebarInk || base.ink, sidebar);
            adjusted.sidebarMuted = controlTextInk(custom.text || base.sidebarMuted || base.muted, sidebar);
        }
        if (custom.content || custom.text) {
            const center = layers.content || base.background;
            adjusted.ink = controlTextInk(text, center);
            adjusted.text = adjusted.ink;
            adjusted.muted = controlTextInk(muted, center);
            adjusted.rowSelectionInk = controlTextInk(custom.text || base.rowSelectionInk || base.ink,
                base.rowSelectionFill || center);
            adjusted.summaryInk = controlTextInk(custom.text || base.summaryInk || base.ink,
                adjusted.summaryFill || base.summaryFill || layers.summary || center);
        }
        if (custom.header || custom.content || custom.text) {
            adjusted.titleInk = controlTextInk(custom.text || base.titleInk || base.ink, layers.title || base.background);
            adjusted.titleMuted = controlTextInk(custom.text || base.titleMuted || base.muted, layers.title || base.background);
        }
        if (custom.footer || custom.content || custom.text) {
            adjusted.footerInk = controlTextInk(text, layers.footer || base.background);
            adjusted.footerMuted = controlTextInk(muted, layers.footer || base.background);
            adjusted.footerDestructive = controlTextInk(base.destructive, layers.footer || base.background);
        }
        if (base.mdm) {
            adjusted.mdm = Object.assign({}, base.mdm, {
                caption: layers.title, tree: layers.sidebar, list: layers.content, field: layers.field,
                menu: adjusted.menuSurface || base.mdm.menu,
                text: adjusted.text || base.mdm.text, muted: adjusted.muted || base.mdm.muted,
                selectionText: adjusted.rowSelectionInk || base.mdm.selectionText
            });
        }
        return Object.assign({}, base, adjusted);
    }

    function resolvedPalette(selection, fallback, role) {
        return selection === "material" ? palette.indicatorDefaults?.[role]?.palette || palette.indicatorPalette || fallback
            : selection;
    }

    function colorsFor(selection, effective, role) {
        if (selection === "material") {
            const colors = palette.indicatorDefaults?.[role]?.colors || palette.liquidColors;
            if (colors)
                return colors;
        }
        return indicatorColors(effective);
    }

    function indicatorColors(id) {
        return (Object.prototype.hasOwnProperty.call(indicatorPalettes, id)
            ? indicatorPalettes[id] : indicatorPalettes["blue-purple"]).colors;
    }

    function neonTone(color) {
        const source = rgba(color, 1);
        const saturation = source.hsvSaturation;
        const hue = source.hsvHue < 0 ? .60 : source.hsvHue;
        const chroma = saturation < .16 ? Math.max(.08, saturation) : .58 + .42 * saturation;
        const glow = Qt.hsva(hue, chroma, Math.min(1, Math.max(.90, source.hsvValue * 1.13)), 1);
        return {
            core: mix(glow, "#030610", .79, 1),
            body: mix(glow, "#071023", .46, 1),
            glow: glow,
            edge: mix(glow, "#eff9ff", .28, 1)
        };
    }

    function safeAccent(color, light) {
        const value = rgba(color, 1);
        const luma = value.r * .213 + value.g * .715 + value.b * .072;
        return light && luma > .58 ? mix(value, "#10192b", .34, 1)
            : !light && luma < .36 ? mix(value, "#edf4ff", .34, 1) : value;
    }

    function withAccent(profile) {
        const accent = safeAccent(forcedAccent || profile.accent, profile.light);
        const text = profile.cleanStudio ? profile.ink : mix(profile.ink, accent, profile.light ? .10 : .16, 1);
        const muted = profile.cleanStudio ? profile.muted : mix(profile.muted, accent, profile.light ? .14 : .22, 1);
        const tones = { ink: text, text: text, muted: muted };
        if (forcedAccent) {
            tones.accent = accent;
            tones.secondary = mix(accent, profile.secondary, .30, 1);
            tones.edge = mix(profile.edge, accent, .48, 1);
            if (profile.cleanStudio) {
                tones.navigationFill = mix(profile.background, accent, .16, 1);
                tones.navigationInk = accent;
            }
        }
        return Object.assign({}, profile, tones);
    }

    function relativeLuminance(color) {
        const value = rgba(color, 1);
        const linear = channel => channel <= .04045 ? channel / 12.92 : Math.pow((channel + .055) / 1.055, 2.4);
        return .2126 * linear(value.r) + .7152 * linear(value.g) + .0722 * linear(value.b);
    }

    function contrastInk(color) {
        return relativeLuminance(color) < .179 ? "#ffffff" : "#000000";
    }

    function contrastRatio(first, second) {
        const left = relativeLuminance(first);
        const right = relativeLuminance(second);
        return (Math.max(left, right) + .05) / (Math.min(left, right) + .05);
    }

    function controlTextInk(preferred, face) {
        return contrastRatio(preferred, face) >= 4.5 ? preferred : contrastInk(face);
    }

    function controlHighlight(color, pressed, hovered) {
        const value = rgba(color, 1);
        if (!pressed && !hovered) return value;
        return Qt.hsva(Math.max(0, value.hsvHue), Math.min(.98, value.hsvSaturation * 1.08),
            pressed ? value.hsvValue * .81 : Math.min(1, value.hsvValue * 1.12), 1);
    }

    function vividControlAccent(color, light) {
        const value = rgba(color, 1);
        const saturation = value.hsvSaturation;
        return Qt.hsva(Math.max(0, value.hsvHue), saturation < .12 ? saturation
            : Math.min(.96, saturation * 1.19 + .07), Math.min(light ? .91 : .98, value.hsvValue), 1);
    }

    function controlPigment(accent, secondary, weight) {
        const primary = rgba(accent, 1);
        const tint = mix(primary, secondary, weight, 1);
        return Qt.hsva(Math.max(0, tint.hsvHue), Math.max(tint.hsvSaturation, primary.hsvSaturation * .91),
            tint.hsvValue, 1);
    }

    function controlIdleStrength(profile, finish) {
        return (finish.idle + (profile.buttonChroma || 0)) * (profile.light ? .65 : 1);
    }

    function controlIconInk(accent, face) {
        const value = rgba(accent, 1);
        const background = relativeLuminance(face);
        const legible = color => {
            const luminance = relativeLuminance(color);
            return (Math.max(luminance, background) + .05) / (Math.min(luminance, background) + .05) >= 3;
        };
        if (legible(value)) return value;
        const text = contrastInk(face);
        const onLight = background >= .179;
        const hue = Math.max(0, value.hsvHue);
        const saturation = value.hsvSaturation;
        const shaded = Qt.hsva(hue, onLight ? saturation : saturation * .50, onLight ? .31 : .99, 1);
        if (legible(shaded)) return shaded;
        const tinted = mix(text, value, .66, 1);
        return legible(tinted) ? tinted : mix(text, value, .16, 1);
    }

    function menuPalette(profile) {
        const pure = rgba(profile.accent, 1);
        const hue = pure.hsvSaturation > .12 ? pure.hsvHue : .62;
        const vivid = Qt.hsva(hue, Math.max(.75, pure.hsvSaturation), profile.light ? 1 : .74, 1);
        const customHighlight = !forcedAccent && profile.menuHighlight;
        const highlight = customHighlight || (profile.light ? mix(vivid, "#ffffff", .42, 1) : vivid);
        const lightInk = relativeLuminance(highlight) < .179;
        const surface = profile.menuSurface || mix(profile.background, profile.light ? "#ffffff" : "#080b15",
            profile.light ? .47 : .27, 1);
        const customized = Boolean(profile.menuOverride || profile.textOverride || profile.contentOverride);
        const preferred = profile.textOverride || profile.ink;
        return {
            studio: profile.cleanStudio === true,
            showShortcuts: profile.cleanStudio === true && profile.light,
            surface: surface,
            ink: customized ? controlTextInk(preferred, surface) : profile.ink,
            muted: customized ? controlTextInk(profile.textOverride || profile.muted, surface) : profile.muted,
            icon: customized ? controlIconInk(profile.accent, surface)
                : profile.cleanStudio ? profile.ink : safeAccent(profile.accent, profile.light),
            danger: customized ? controlTextInk(profile.destructive, surface) : profile.destructive,
            border: rgba(profile.surfaceLine || profile.divider, profile.cleanStudio ? .91 : .42),
            highlight: highlight,
            highlightInk: customized ? controlTextInk(preferred, highlight) : lightInk ? "#ffffff" : "#050810",
            pressed: mix(highlight, lightInk ? "#000000" : "#ffffff", .15, 1),
            rail: customHighlight && profile.menuRail ? profile.menuRail : lightInk ? "#a9f5ff" : "#101e35"
        };
    }

    readonly property var buttonPresets: ({
        cool: {accent: "#5475dc", secondary: "#9273d9", positive: "#1da58b", caution: "#d9a34f", destructive: "#d8537c"},
        warm: {accent: "#dd8257", secondary: "#be6e9e", positive: "#478b61", caution: "#d1a048", destructive: "#c64f61"}
    })

    readonly property var actionHues: ({
        add: ["#55f38e", "#077d48"], torrent: ["#adf766", "#537b0a"],
        start: ["#42d9ff", "#00779d"], pause: ["#ffc44e", "#976007"],
        stop: ["#ff8e75", "#b14435"], remove: ["#ff7498", "#c03259"],
        check: ["#f68bc8", "#a93478"], settings: ["#c09aff", "#6d35bc"],
        clock: ["#67e8e9", "#007d82"], queueStart: ["#8d9dff", "#4a4cc2"],
        queueStop: ["#e9a4ff", "#893bb2"], downloads: ["#ff8d9c", "#aa3050"],
        activity: ["#58e0bd", "#077967"], complete: ["#9ce57e", "#437623"],
        tray: ["#88efb6", "#097c5c"], minimize: ["#69dbff", "#0877a5"],
        maximize: ["#bd9fff", "#6941a6"], file: ["#ffbd73", "#976020"],
        details: ["#a5afff", "#5149ab"], keys: ["#e2a2f7", "#8d3aa8"]
    })
    readonly property var actionButtonRoles: ({
        add: "positive", torrent: "positive", start: "positive", activity: "positive", complete: "positive",
        pause: "caution", file: "caution", stop: "destructive", remove: "destructive",
        check: "secondary", clock: "secondary", keys: "secondary", queueStop: "secondary", maximize: "secondary"
    })

    function buttonRole(fallback, material) {
        const base = profile(material);
        for (const role of ["accent", "positive", "caution", "destructive", "secondary"]) {
            if (Qt.colorEqual(fallback, base[role]))
                return role;
        }
        for (const symbol of Object.keys(actionButtonRoles)) {
            if (actionHues[symbol].some(color => Qt.colorEqual(fallback, color)))
                return actionButtonRoles[symbol];
        }
        return "accent";
    }

    function buttonColorOverride(material, fallback, role = "") {
        const custom = materialCustomizations[material];
        const mode = custom?.buttonPalette;
        const colors = mode === "custom" ? custom.buttonColors : buttonPresets[mode];
        return colors?.[role || buttonRole(fallback, material)] || "";
    }

    function buttonTint(material, fallback, role = "") {
        return buttonColorOverride(material, fallback, role) || forcedAccent || fallback;
    }

    function actionColor(symbol, light) {
        const colors = actionHues[symbol];
        return colors ? colors[light ? 1 : 0] : palette.accent;
    }

    function navigationColor(index, light) {
        const keys = ["downloads", "activity", "settings", "pause", "start", "complete", "keys"];
        return actionColor(keys[index % keys.length], light);
    }

    function mix(value, other, weight, alpha) {
        const a = rgba(value, alpha);
        const b = rgba(other, alpha);
        return Qt.rgba(a.r + (b.r - a.r) * weight, a.g + (b.g - a.g) * weight,
            a.b + (b.b - a.b) * weight, alpha);
    }

    function exportMaterial(id) {
        if (Object.prototype.hasOwnProperty.call(userMaterials, id))
            return Object.assign({}, userMaterials[id]);
        const style = profile(id);
        return {
            format: "auralis-material", version: 1, name: style.name,
            finish: style.finish, controls: style.controls,
            translucency: Math.round(style.translucency * 100), shading: Math.round(style.gloss * 100)
        };
    }

    function installMaterial(value) {
        if (!value || value.format !== "auralis-material" || value.version !== 1 || typeof value.name !== "string")
            return "";
        const name = value.name.trim();
        if (name.length < 1 || name.length > 50
            || !["matte", "satin", "gloss", "frosted", "clear"].includes(value.finish)
            || !["rounded", "soft", "angular"].includes(value.controls)
            || !Number.isFinite(value.translucency) || value.translucency < 0 || value.translucency > 100
            || !Number.isFinite(value.shading) || value.shading < 0 || value.shading > 100
            || (value.layout !== undefined && !["compact", "standard", "spacious"].includes(value.layout))
            || (value.text !== undefined && !["crisp", "soft"].includes(value.text)))
            return "";

        // Preserve the UTF-8 identifier used in portable Auralis material files.
        let encoded;
        try { encoded = encodeURIComponent(name.toLowerCase()); }
        catch (error) { return ""; }
        let id = "custom-";
        for (let index = 0; index < encoded.length; ++index) {
            if (encoded[index] === "%") {
                id += encoded.substring(index + 1, index + 3).toLowerCase();
                index += 2;
            } else {
                id += ("0" + encoded.charCodeAt(index).toString(16)).slice(-2);
            }
        }
        if (Object.keys(userMaterials).length >= 32 && !userMaterials[id])
            return "";
        const material = {
            format: "auralis-material", version: 1, name: name, finish: value.finish,
            controls: value.controls, translucency: value.translucency, shading: value.shading
        };
        if (value.layout !== undefined)
            material.layout = value.layout;
        if (value.text !== undefined)
            material.text = value.text;
        const updated = Object.assign({}, userMaterials);
        updated[id] = material;
        userMaterials = updated;
        return id;
    }

    function opacityFor(id) {
        if (isMdmPreset(id))
            return 1;
        const style = profile(id);
        const amount = translucency >= 0 ? translucency : style.opaque ? 0 : style.translucency;
        return Math.max(0, Math.min(1, 1 - amount));
    }

    function rgba(value, alpha) {
        if (value && typeof value.r === "number")
            return Qt.rgba(value.r, value.g, value.b, alpha);
        const hex = String(value).slice(-6);
        const rgb = parseInt(hex, 16);
        return Qt.rgba(((rgb >> 16) & 255) / 255, ((rgb >> 8) & 255) / 255, (rgb & 255) / 255, alpha);
    }

    function tint(value, alpha) {
        const base = rgba(value, alpha);
        const blend = Math.max(0, Math.min(1, tintStrength)) * 0.42;
        return Qt.rgba(base.r + (tintColor.r - base.r) * blend,
                       base.g + (tintColor.g - base.g) * blend,
                       base.b + (tintColor.b - base.b) * blend, alpha);
    }
}
