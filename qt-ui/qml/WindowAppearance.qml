pragma Singleton

import QtQuick
import QtCore

QtObject {
    id: root

    property bool loaded: false
    property var preferences: defaults()
    readonly property string progressShape: preferences.progressShape
    readonly property string progressFill: preferences.progressFill
    readonly property string connectionShape: preferences.connectionShape
    readonly property string connectionFill: preferences.connectionFill
    readonly property string graphShape: preferences.graphShape

    property Settings persistence: Settings {
        category: "WindowAppearance"
        property string saved: ""
    }

    property Connections materialPersistence: Connections {
        target: MaterialTheme
        function onCurrentChanged() { root.store() }
        function onTranslucencyChanged() { root.store() }
        function onTintColorChanged() { root.store() }
        function onTintStrengthChanged() { root.store() }
        function onReducedMotionChanged() { root.store() }
        function onUserMaterialsChanged() { root.store() }
        function onColorThemeChanged() { root.store() }
    }

    onPreferencesChanged: store()
    Component.onCompleted: {
        if (persistence.saved) {
            try { applyBackup(JSON.parse(persistence.saved), true) }
            catch (error) { console.warn("Could not restore appearance preferences", String(error)) }
        }
        loaded = true
    }

    function defaults() {
        return {
            mainMode: "desktop", detailsMode: "desktop", mainMedia: "", detailsMedia: "",
            mainColor: "", detailsColor: "", progressShape: "material", progressFill: "sculpted",
            connectionShape: "material", connectionFill: "sculpted", graphShape: "area"
        }
    }

    function set(key, value) {
        preferences = Object.assign({}, preferences, {[key]: value})
    }

    function background(target) {
        const prefix = target === "main" ? "main" : "details"
        return {
            mode: preferences[prefix + "Mode"],
            media: preferences[prefix + "Media"],
            color: preferences[prefix + "Color"]
        }
    }

    function fileUrl(path) {
        const value = String(path || "").replace(/\\/g, "/")
        if (value.startsWith("file:")) return value
        if (!/^(?:\/|[A-Za-z]:\/)/.test(value)) return ""
        const encoded = value.split("/").map((part, index) =>
            index === 0 && /^[A-Za-z]:$/.test(part) ? part : encodeURIComponent(part)).join("/")
        return encoded.startsWith("//") ? "file:" + encoded
            : encoded.startsWith("/") ? "file://" + encoded : "file:///" + encoded
    }

    function colorText(color) {
        const channel = value => Math.round(value * 255).toString(16).padStart(2, "0")
        return typeof color === "string" ? color : "#" + channel(color.r) + channel(color.g) + channel(color.b)
    }

    function colorValid(value) {
        return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value)
    }

    function validPalette(value) {
        if (!value || typeof value.name !== "string" || !value.name.trim() || value.name.length > 50 ||
            !colorValid(value.accent) || !colorValid(value.secondary) || typeof value.light !== "boolean")
            return false
        if (value.surface === null) return !value.light
        if (!Array.isArray(value.surface) || value.surface.length !== 3 ||
            !value.surface.every(channel => Number.isInteger(channel) && channel >= 0 && channel <= 255))
            return false
        const brightness = .2126 * value.surface[0] + .7152 * value.surface[1] + .0722 * value.surface[2]
        return value.light ? brightness >= 150 : brightness <= 190
    }

    function optionalColor(value, fallback) {
        return value === "" || colorValid(value) ? value : fallback
    }

    function validChoice(value, choices, fallback) {
        return choices.includes(value) ? value : fallback
    }

    function indicatorShape(value, fallback) {
        const decoded = {rounded: "round", faceted: "prism", droplet: "bubble"}
        return validChoice(decoded[value] || value, ["material", "round", "square", "bubble", "prism", "ice"], fallback)
    }

    function store() {
        if (loaded) persistence.saved = JSON.stringify(snapshot())
    }

    function snapshot() {
        const shape = value => ({round: "rounded", ice: "faceted", prism: "faceted", material: "rounded"})[value] || value
        const result = {
            "mh-glass-material": MaterialTheme.current,
            "mh-glass-custom-materials": JSON.stringify(Object.values(MaterialTheme.userMaterials)),
            "mh-glass-tint-strength": String(Math.round(MaterialTheme.tintStrength * 65)),
            "mh-glass-back-main": preferences.mainMode,
            "mh-glass-back-details": preferences.detailsMode,
            "mh-glass-solid-main": preferences.mainColor,
            "mh-glass-solid-details": preferences.detailsColor,
            "mh-glass-wall-main": preferences.mainMedia ? engine.localPath(fileUrl(preferences.mainMedia)) : "",
            "mh-glass-wall-detail": preferences.detailsMedia ? engine.localPath(fileUrl(preferences.detailsMedia)) : "",
            "mh-glass-progress-shape": shape(progressShape),
            "mh-glass-progress-material": progressFill === "default" ? "gradient" : "liquid-glass",
            "mh-glass-connection-shape": shape(connectionShape),
            "mh-glass-connection-material": connectionFill === "default" ? "gradient" : "liquid-glass",
            "mh-glass-graph-shape": graphShape,
            "mh-glass-qt-appearance": JSON.stringify(Object.assign({}, preferences, {
                tint: colorText(MaterialTheme.tintColor),
                colorTheme: MaterialTheme.colorTheme,
                reducedMotion: MaterialTheme.reducedMotion
            }))
        }
        if (MaterialTheme.translucency >= 0)
            result["mh-glass-glass-translucency"] = String(Math.round(MaterialTheme.translucency * 100))
        return result
    }

    function applyBackup(data, complete) {
        if (!data || typeof data !== "object") return
        let saved = {}
        try { saved = JSON.parse(data["mh-glass-qt-appearance"] || "{}") || {} }
        catch (error) { console.warn("Could not load stored Qt appearance options", String(error)) }
        if (complete) MaterialTheme.userMaterials = ({})
        try {
            const materials = JSON.parse(data["mh-glass-custom-materials"] || "[]")
            if (Array.isArray(materials)) materials.slice(0, 32).forEach(material => MaterialTheme.installMaterial(material))
        } catch (error) { console.warn("Could not load stored materials", String(error)) }

        const value = data["mh-glass-material"]
        if (typeof value === "string" && (MaterialTheme.builtins[value] || MaterialTheme.userMaterials[value]))
            MaterialTheme.current = value
        else if (complete)
            MaterialTheme.current = "builtin-aurora-night"
        const translucency = Number(data["mh-glass-glass-translucency"])
        if (Number.isFinite(translucency) && translucency >= 0 && translucency <= 100)
            MaterialTheme.translucency = translucency / 100
        else if (complete)
            MaterialTheme.translucency = -1
        const strength = Number(data["mh-glass-tint-strength"])
        if (Number.isFinite(strength)) MaterialTheme.tintStrength = Math.max(0, Math.min(1, strength / 65))
        else if (complete) MaterialTheme.tintStrength = 0
        if (colorValid(saved.tint)) MaterialTheme.tintColor = saved.tint
        else if (complete) MaterialTheme.tintColor = "#7298bc"
        if (typeof saved.reducedMotion === "boolean") MaterialTheme.reducedMotion = saved.reducedMotion
        else if (complete) MaterialTheme.reducedMotion = false
        if (validPalette(saved.colorTheme)) MaterialTheme.colorTheme = saved.colorTheme
        else if (complete) MaterialTheme.colorTheme = null

        const original = complete ? defaults() : preferences
        const modes = ["desktop", "solid", "wallpaper"]
        preferences = {
            mainMode: validChoice(saved.mainMode || data["mh-glass-back-main"], modes, original.mainMode),
            detailsMode: validChoice(saved.detailsMode || data["mh-glass-back-details"], modes, original.detailsMode),
            mainMedia: fileUrl(saved.mainMedia ?? data["mh-glass-wall-main"] ?? original.mainMedia),
            detailsMedia: fileUrl(saved.detailsMedia ?? data["mh-glass-wall-detail"] ?? original.detailsMedia),
            mainColor: optionalColor(saved.mainColor ?? data["mh-glass-solid-main"], original.mainColor),
            detailsColor: optionalColor(saved.detailsColor ?? data["mh-glass-solid-details"], original.detailsColor),
            progressShape: indicatorShape(saved.progressShape || data["mh-glass-progress-shape"], original.progressShape),
            progressFill: validChoice(saved.progressFill, ["default", "sculpted"],
                data["mh-glass-progress-material"] === "gradient" ? "default" : original.progressFill),
            connectionShape: indicatorShape(saved.connectionShape || data["mh-glass-connection-shape"], original.connectionShape),
            connectionFill: validChoice(saved.connectionFill, ["default", "sculpted"],
                data["mh-glass-connection-material"] === "gradient" ? "default" : original.connectionFill),
            graphShape: validChoice(saved.graphShape || data["mh-glass-graph-shape"], ["area", "line", "bars"], original.graphShape)
        }
    }

    function exportTheme() {
        const profile = MaterialTheme.palette
        const material = MaterialTheme.current
        const builtIn = ["brushed-glass", "frosted-water-351", "rose-pine", "window-glass", "oversimplified",
            "builtin-obsidian-matte", "builtin-smoked-glass", "builtin-black-glass", "builtin-pearl-frost",
            "builtin-aurora-night", "builtin-aurora-ice"].includes(material)
        const legacy = snapshot()
        const rgb = colorText(profile.background).slice(1).match(/../g).map(component => parseInt(component, 16))
        return {
            format: "auralis-theme", version: 1,
            palette: MaterialTheme.colorTheme || {name: profile.name, accent: colorText(profile.accent),
                secondary: colorText(profile.secondary), surface: rgb, light: profile.light},
            material: builtIn ? material : "custom",
            customMaterial: builtIn ? null : MaterialTheme.exportMaterial(material),
            settings: {
                glassTranslucency: MaterialTheme.translucency < 0 ? null : Math.round(MaterialTheme.translucency * 100),
                tintStrength: Math.round(MaterialTheme.tintStrength * 65), fontFamily: "Segoe UI", fontSize: 14,
                highContrast: true, uiScale: 100, dim: 26, blur: 6, indicator: "aurora",
                connectionIndicator: "aurora", graphIndicator: "aurora", progressMaterial: legacy["mh-glass-progress-material"],
                connectionMaterial: legacy["mh-glass-connection-material"], graphMaterial: "gradient",
                progressShape: legacy["mh-glass-progress-shape"], connectionShape: legacy["mh-glass-connection-shape"],
                graphShape: graphShape, trackFinish: "recessed", trackColor: "ice",
                connectionTrackFinish: "recessed", connectionTrackColor: "ice"
            },
            qt: {material: material, tint: colorText(MaterialTheme.tintColor), progressShape: progressShape,
                connectionShape: connectionShape, reducedMotion: MaterialTheme.reducedMotion}
        }
    }

    function importTheme(value) {
        if (!value || value.format !== "auralis-theme" || value.version !== 1 || !validPalette(value.palette) ||
            !value.settings || typeof value.settings !== "object")
            return false
        const options = value.settings
        const tint = value.qt ? value.qt.tint : value.palette.accent
        if (options.glassTranslucency !== null && options.glassTranslucency !== undefined &&
            (!Number.isInteger(options.glassTranslucency) || options.glassTranslucency < 0 || options.glassTranslucency > 100))
            return false
        if (!Number.isFinite(options.tintStrength) || options.tintStrength < 0 || options.tintStrength > 65)
            return false
        let material = value.material
        if (material === "custom") {
            if (value.qt && MaterialTheme.builtins[value.qt.material]) material = value.qt.material
            else material = MaterialTheme.installMaterial(value.customMaterial)
        }
        if (!(MaterialTheme.builtins[material] || MaterialTheme.userMaterials[material])) return false
        MaterialTheme.current = material
        MaterialTheme.colorTheme = value.palette
        MaterialTheme.translucency = typeof options.glassTranslucency === "number" ? options.glassTranslucency / 100 : -1
        MaterialTheme.tintStrength = options.tintStrength / 65
        if (colorValid(tint)) MaterialTheme.tintColor = tint
        if (value.qt && typeof value.qt.reducedMotion === "boolean") MaterialTheme.reducedMotion = value.qt.reducedMotion
        set("progressShape", indicatorShape(value.qt?.progressShape || options.progressShape, progressShape))
        set("connectionShape", indicatorShape(value.qt?.connectionShape || options.connectionShape, connectionShape))
        set("progressFill", options.progressMaterial === "gradient" ? "default" : "sculpted")
        set("connectionFill", options.connectionMaterial === "gradient" ? "default" : "sculpted")
        set("graphShape", validChoice(options.graphShape, ["area", "line", "bars"], graphShape))
        return true
    }
}
