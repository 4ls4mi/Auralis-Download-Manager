pragma Singleton

import QtQuick

QtObject {
    id: theme

    readonly property string defaultMaterial: "carbon"
    property string current: defaultMaterial
    property real translucency: -1
    property color tintColor: "#7298bc"
    property real tintStrength: 0
    property bool backdropAvailable: false
    property bool reducedMotion: false
    property var userMaterials: ({})
    property var colorTheme: null
    property string forcedAccent: ""
    property string progressPalette: "blue-purple"
    property string connectionPalette: "ocean"
    property string graphPalette: "blue-purple"

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
        forest: { label: qsTr("Forest"), colors: ["#aef244", "#049c91"] }
    })
    readonly property var indicatorChoices: Object.keys(indicatorPalettes).map(id =>
        ({ value: id, label: indicatorPalettes[id].label }))
    readonly property var progressColors: indicatorColors(progressPalette)
    readonly property var connectionColors: indicatorColors(connectionPalette)
    readonly property var graphColors: indicatorColors(graphPalette)

    readonly property var builtins: ({
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
            name: qsTr("Prism Glass"), finish: "gloss", shape: "prism",
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
    readonly property var materials: Object.keys(builtins)
        .filter(id => id !== "window-glass")
        .concat(Object.keys(userMaterials))
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
        let result = Object.prototype.hasOwnProperty.call(builtins, id) ? builtins[id] : builtins[defaultMaterial];
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
            return withAccent(result);

        const light = colorTheme.light === true;
        const contrast = preset({ light: light, shape: result.shape });
        const rgb = colorTheme.surface;
        const surface = rgb && rgb.length === 3
            ? Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1) : light ? "#e8f1fa" : "#172135";
        const ground = rgba(surface, 1);
        const tone = rgba(colorTheme.accent, 1);
        return withAccent(Object.assign({}, result, {
            light: light, text: contrast.text, ink: contrast.ink, muted: contrast.muted,
            divider: contrast.divider, positive: contrast.positive, caution: contrast.caution,
            destructive: contrast.destructive, accent: colorTheme.accent, secondary: colorTheme.secondary,
            background: Qt.rgba(ground.r * .78 + tone.r * .22, ground.g * .78 + tone.g * .22,
                                ground.b * .78 + tone.b * .22, 1)
        }));
    }

    function indicatorColors(id) {
        return (Object.prototype.hasOwnProperty.call(indicatorPalettes, id)
            ? indicatorPalettes[id] : indicatorPalettes["blue-purple"]).colors;
    }

    function safeAccent(color, light) {
        const value = rgba(color, 1);
        const luma = value.r * .213 + value.g * .715 + value.b * .072;
        return light && luma > .58 ? mix(value, "#10192b", .34, 1)
            : !light && luma < .36 ? mix(value, "#edf4ff", .34, 1) : value;
    }

    function withAccent(profile) {
        if (!forcedAccent) return profile;
        const accent = safeAccent(forcedAccent, profile.light);
        return Object.assign({}, profile, {
            accent: accent,
            secondary: mix(accent, profile.secondary, .30, 1),
            edge: mix(profile.edge, accent, .48, 1)
        });
    }

    function actionColor(symbol, light) {
        const hues = {
            add: ["#55f38e", "#077d48"], torrent: ["#adf766", "#537b0a"],
            start: ["#42d9ff", "#00779d"], pause: ["#ffc44e", "#976007"],
            stop: ["#ff8e75", "#b14435"], remove: ["#ff7498", "#c03259"],
            check: ["#f68bc8", "#a93478"], settings: ["#c09aff", "#6d35bc"],
            clock: ["#67e8e9", "#007d82"], queueStart: ["#8d9dff", "#4a4cc2"],
            queueStop: ["#e9a4ff", "#893bb2"]
        };
        const colors = hues[symbol];
        return colors ? colors[light ? 1 : 0] : palette.accent;
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
        const style = profile(id);
        return style.opaque ? 1 : Math.max(0, Math.min(1, 1 - (translucency >= 0 ? translucency : style.translucency)));
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
