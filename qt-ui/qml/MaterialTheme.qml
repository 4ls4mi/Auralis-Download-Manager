pragma Singleton

import QtQuick

QtObject {
    id: theme

    property string current: "builtin-aurora-night"
    property real translucency: -1
    property color tintColor: "#7298bc"
    property real tintStrength: 0
    property bool backdropAvailable: false
    property bool reducedMotion: false
    property var userMaterials: ({})
    property var colorTheme: null

    readonly property var builtins: ({
        "builtin-aurora-night": preset({
            name: qsTr("Aurora Glass — Dark"), finish: "frosted", shape: "chamfer",
            background: "#141731", edge: "#a4c8ff", accent: "#58dbff", secondary: "#b57bff",
            shade: "#05091f", upper: "#d2e0ff", translucency: 0.72, gloss: 0.72, radius: 14, bevel: 4
        }),
        "builtin-aurora-ice": preset({
            name: qsTr("Aurora Glass — Light"), finish: "frosted", shape: "ice", light: true,
            background: "#cfeaff", edge: "#f2feff", accent: "#086797", secondary: "#704bc3",
            shade: "#2a638e", upper: "#fcffff", translucency: 0.78, gloss: 0.86, radius: 11, bevel: 5
        }),
        "water-bubble": preset({
            name: qsTr("Water Bubble"), finish: "gloss", shape: "bubble",
            background: "#172852", edge: "#a3e4ff", accent: "#6cecff", secondary: "#db8bff",
            shade: "#090e31", upper: "#ecfcff", translucency: 0.78, gloss: 0.95, radius: 22, bevel: 7
        }),
        "ice-edge": preset({
            name: qsTr("Ice Edge"), finish: "clear", shape: "ice", light: true,
            background: "#c7dfee", edge: "#f4ffff", accent: "#12648c", secondary: "#4c5fbf",
            shade: "#37506e", upper: "#f6ffff", translucency: 0.7, gloss: 0.78, radius: 14, bevel: 5
        }),
        "prismatic-glass": preset({
            name: qsTr("Prismatic Glass"), finish: "gloss", shape: "prism",
            background: "#201d3e", edge: "#d6c3ff", accent: "#adf3f8", secondary: "#eea4fb",
            shade: "#130c2c", upper: "#fff5ff", translucency: 0.73, gloss: 0.94, radius: 17, bevel: 6
        }),
        "smoked-crystal": preset({
            name: qsTr("Smoked Crystal"), finish: "satin", shape: "smoke",
            background: "#241c23", edge: "#e9ba97", accent: "#fad19f", secondary: "#bf9eba",
            shade: "#120b18", upper: "#fde4c4", translucency: 0.7, gloss: 0.44, radius: 10, bevel: 4
        }),
        "frosted-water-351": preset({
            name: qsTr("Frosted Layers"), finish: "frosted", shape: "frost",
            background: "#193d54", edge: "#b5edfa", accent: "#7ce7fa", secondary: "#c1bbff",
            shade: "#102543", upper: "#e3fcff", translucency: 0.57, gloss: 0.66, radius: 18, bevel: 5
        }),
        "aero-gloss": preset({
            name: qsTr("Aero Gloss"), finish: "gloss", shape: "aero",
            background: "#163044", edge: "#c0f5ff", accent: "#8cd7ff", secondary: "#75ecca",
            shade: "#07182b", upper: "#f2ffff", translucency: 0.7, gloss: 0.9, radius: 14, bevel: 5
        }),
        "brushed-glass": preset({
            name: qsTr("Brushed Glass"), finish: "satin", shape: "chamfer",
            background: "#18363e", edge: "#9dd9d3", accent: "#84ecd2", secondary: "#abdefc",
            shade: "#0b2429", upper: "#c9eeea", translucency: 0.74, gloss: 0.51, radius: 5, bevel: 3
        }),
        "rose-pine": preset({
            name: qsTr("Rose Pine"), finish: "matte", shape: "aero",
            background: "#3c2436", edge: "#e7bad1", accent: "#f4b6cf", secondary: "#ebba96",
            shade: "#2b1127", upper: "#ffe0e6", translucency: 0.64, gloss: 0.41, radius: 16, bevel: 4
        }),
        "oversimplified": preset({
            name: qsTr("Oversimplified & Accentuated"), finish: "matte", shape: "plain",
            background: "#181839", edge: "#9290c8", accent: "#b4baff", secondary: "#91dfc8",
            shade: "#12152d", upper: "#d4d5ff", translucency: 0.83, gloss: 0.23, radius: 3, bevel: 2
        }),
        "builtin-obsidian-matte": preset({
            name: qsTr("Matte Obsidian"), finish: "matte", shape: "chamfer",
            background: "#282523", edge: "#d2ae80", accent: "#f3c988", secondary: "#f29f64",
            shade: "#141015", upper: "#ffdea6", translucency: 0.52, gloss: 0.27, radius: 5, bevel: 3
        }),
        "builtin-smoked-glass": preset({
            name: qsTr("Smoked Glass"), finish: "clear", shape: "smoke",
            background: "#382e29", edge: "#edc193", accent: "#f8c689", secondary: "#c7a787",
            shade: "#201720", upper: "#ffdfb4", translucency: 0.67, gloss: 0.52, radius: 12, bevel: 4
        }),
        "builtin-black-glass": preset({
            name: qsTr("Black Blur Glass"), finish: "clear", shape: "round",
            background: "#101219", edge: "#b6c0d1", accent: "#c0d4e8", secondary: "#92b4dc",
            shade: "#06070c", upper: "#e1ebf4", translucency: 0.8, gloss: 0.48, radius: 9, bevel: 3
        }),
        "builtin-pearl-frost": preset({
            name: qsTr("Pearl Frost"), finish: "frosted", shape: "frost", light: true,
            background: "#f1e5eb", edge: "#fbf4ff", accent: "#804a94", secondary: "#27687c",
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
        let result = Object.prototype.hasOwnProperty.call(builtins, id) ? builtins[id] : builtins["builtin-aurora-night"];
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
            return result;

        const light = colorTheme.light === true;
        const contrast = preset({ light: light, shape: result.shape });
        const rgb = colorTheme.surface;
        const surface = rgb && rgb.length === 3
            ? Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1) : light ? "#e8f1fa" : "#172135";
        const ground = rgba(surface, 1);
        const tone = rgba(colorTheme.accent, 1);
        return Object.assign({}, result, {
            light: light, text: contrast.text, ink: contrast.ink, muted: contrast.muted,
            divider: contrast.divider, positive: contrast.positive, caution: contrast.caution,
            destructive: contrast.destructive, accent: colorTheme.accent, secondary: colorTheme.secondary,
            background: Qt.rgba(ground.r * .78 + tone.r * .22, ground.g * .78 + tone.g * .22,
                                ground.b * .78 + tone.b * .22, 1)
        });
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
        return Math.max(0, Math.min(1, 1 - (translucency >= 0 ? translucency : profile(id).translucency)));
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
