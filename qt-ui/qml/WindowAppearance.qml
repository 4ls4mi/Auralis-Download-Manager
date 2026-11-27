pragma Singleton

import QtQuick
import QtCore

QtObject {
    id: root

    property bool loaded: false
    property var preferences: defaults()
    readonly property int cornerRadius: preferences.cornerRadius
    readonly property string cornerPlacement: preferences.cornerPlacement
    readonly property string progressShape: preferences.progressShape
    readonly property string progressLayout: preferences.progressLayout
    readonly property int progressThickness: preferences.progressThickness
    readonly property string progressAnimation: preferences.progressAnimation
    readonly property string progressLighting: preferences.progressLighting
    readonly property bool customProgressFill: preferences.customProgressFill
    readonly property string progressTrackFinish: preferences.progressTrackFinish
    readonly property string progressTrackColor: preferences.progressTrackColor
    readonly property var progressTrackColors: trackColors(progressTrackColor)
    readonly property string connectionShape: preferences.connectionShape
    readonly property int connectionBlockSize: preferences.connectionBlockSize
    readonly property string connectionAnimation: preferences.connectionAnimation
    readonly property string connectionLighting: preferences.connectionLighting
    readonly property string graphMaterial: preferences.graphMaterial || "default"
    readonly property var graphMaterialChoices: [
        {label: qsTr("Theme default"), value: "default"},
        {label: qsTr("Jelly glass"), value: "jelly"},
        {label: qsTr("Frosted gel"), value: "frosted"},
        {label: qsTr("Cut crystal"), value: "crystal"},
        {label: qsTr("Satin ribbon"), value: "satin"},
        {label: qsTr("Pearl membrane"), value: "pearl"},
        {label: qsTr("Aurora mesh"), value: "aurora-mesh"},
        {label: qsTr("Carbon contour"), value: "carbon"},
        {label: qsTr("Liquid mercury"), value: "mercury"}
    ]
    readonly property string graphShape: preferences.graphShape
    readonly property string graphAnimation: preferences.graphAnimation
    readonly property string graphLighting: preferences.graphLighting
    readonly property var materialColorRoles: ["header", "footer", "sidebar", "content", "menu", "text"]
    readonly property var buttonColorRoles: ["accent", "secondary", "positive", "caution", "destructive"]
    readonly property var buttonPaletteIds: ["material", "cool", "warm", "custom"]
    readonly property var progressLayoutChoices: [
        {label: qsTr("Classic"), value: "classic"},
        {label: qsTr("Status track"), value: "status-track"},
        {label: qsTr("Pill segments"), value: "pill-segments"},
        {label: qsTr("Thin line"), value: "thin-line"},
        {label: qsTr("Striped fill"), value: "striped-fill"}
    ]
    readonly property var progressTrackFinishChoices: [
        {label: qsTr("Material default"), value: "default"},
        {label: qsTr("Clear glass"), value: "clear"},
        {label: qsTr("Frosted"), value: "frosted"},
        {label: qsTr("Recessed"), value: "recessed"}
    ]
    readonly property var progressTrackTints: ({
        ice: { label: qsTr("Ice"), color: "#a8d8ef" },
        violet: { label: qsTr("Violet"), color: "#9b78d7" },
        teal: { label: qsTr("Teal"), color: "#41b8b3" },
        amber: { label: qsTr("Amber"), color: "#da9b4c" }
    })
    readonly property var progressTrackColorChoices: [{label: qsTr("Material default"), value: "material"}]
        .concat(Object.keys(progressTrackTints).map(id => ({label: progressTrackTints[id].label, value: id})))
        .concat(Object.keys(MaterialTheme.indicatorPalettes).map(id =>
            ({label: MaterialTheme.indicatorPalettes[id].label, value: "palette:" + id})))
    readonly property var animationChoices: [
        {label: qsTr("Classic"), value: "classic"},
        {label: qsTr("Normal (no motion)"), value: "none"},
        {label: qsTr("Gushing water"), value: "water"},
        {label: qsTr("Jelly"), value: "jelly"}
    ]
    readonly property var progressAnimationChoices: animationChoices.concat([
        {label: qsTr("Traveling sheen"), value: "sheen"},
        {label: qsTr("Soft heartbeat"), value: "heartbeat"},
        {label: qsTr("Rolling tide"), value: "tide"},
        {label: qsTr("Elastic gloss"), value: "elastic"},
        {label: qsTr("Prism glints"), value: "glints"},
        {label: qsTr("Current flow"), value: "current"}
    ])
    readonly property var lightingChoices: [
        {label: qsTr("Polished glass"), value: "polished"},
        {label: qsTr("Deep shading"), value: "depth"},
        {label: qsTr("Liquid caustics"), value: "caustics"},
        {label: qsTr("Neon halo"), value: "halo"},
        {label: qsTr("Soft Frost"), value: "frost"},
        {label: qsTr("Chrome Edge"), value: "chrome"},
        {label: qsTr("Bottom Light"), value: "underlit"},
        {label: qsTr("Smoked Glass"), value: "smoke"},
        {label: qsTr("Satin Sweep"), value: "satin"},
        {label: qsTr("Faceted Crystal"), value: "facets"},
        {label: qsTr("Cross Lighting"), value: "cross"},
        {label: qsTr("Pinpoint Gloss"), value: "pinpoint"},
        {label: qsTr("Fluted Glass"), value: "fluted"},
        {label: qsTr("Iridescent Rim"), value: "iridescent"},
        {label: qsTr("Backlit Glass"), value: "backlit"},
        {label: qsTr("Edge-Lit Glass"), value: "edge-lit"}
    ]

    property Settings persistence: Settings {
        category: "WindowAppearance"
        property string saved: ""
    }

    property Connections materialPersistence: Connections {
        target: MaterialTheme
        function onCurrentChanged() { root.store() }
        function onMdmModeChanged() { root.store() }
        function onTranslucencyChanged() { root.store() }
        function onTintColorChanged() { root.store() }
        function onTintStrengthChanged() { root.store() }
        function onReducedMotionChanged() { root.store() }
        function onUserMaterialsChanged() { root.store() }
        function onColorThemeChanged() { root.store() }
        function onForcedAccentChanged() { root.store() }
        function onProgressPaletteChanged() { root.store() }
        function onConnectionPaletteChanged() { root.store() }
        function onGraphPaletteChanged() { root.store() }
    }

    onPreferencesChanged: {
        if (loaded) {
            publishMaterialCustomizations()
            store()
        }
    }
    Component.onCompleted: {
        if (persistence.saved) {
            try { applyBackup(JSON.parse(persistence.saved), true) }
            catch (error) { console.warn("Could not restore appearance preferences", String(error)) }
        }
        publishMaterialCustomizations()
        loaded = true
    }

    function defaults() {
        return {
            cornerRadius: 12, cornerPlacement: "top",
            mainMode: "desktop", detailsMode: "desktop", mainMedia: "", detailsMedia: "",
            mainColor: "", detailsColor: "", progressShape: "material", progressLayout: "classic",
            materialCustomizations: {}, progressThickness: 100, connectionBlockSize: 100,
            customProgressFill: false, progressTrackFinish: "default", progressTrackColor: "material",
            progressAnimation: "classic", progressLighting: "polished", connectionShape: "material",
            connectionAnimation: "classic", connectionLighting: "polished",
            graphMaterial: "default", graphShape: "area", graphAnimation: "classic", graphLighting: "polished"
        }
    }

    function set(key, value) {
        if (key === "progressThickness" || key === "connectionBlockSize")
            value = indicatorSize(value, preferences[key])
        else if (key === "progressTrackFinish")
            value = trackFinishFor(value, progressTrackFinish)
        else if (key === "progressTrackColor")
            value = trackColorFor(value, progressTrackColor)
        else if (key === "customProgressFill" && typeof value !== "boolean")
            return
        if (preferences[key] !== value)
            preferences = Object.assign({}, preferences, {[key]: value})
    }

    function indicatorSize(value, fallback) {
        return Number.isInteger(value) && value >= 60 && value <= 160 ? value : fallback
    }

    function publishMaterialCustomizations() {
        if (MaterialTheme.materialCustomizations !== preferences.materialCustomizations)
            MaterialTheme.materialCustomizations = preferences.materialCustomizations
    }

    function materialCustomization(material) {
        const all = preferences.materialCustomizations
        return Object.prototype.hasOwnProperty.call(all, material) ? all[material] : {}
    }

    function materialColor(material, role) {
        return materialColorRoles.includes(role) ? materialCustomization(material)[role] || "" : ""
    }

    function buttonPalette(material) {
        return materialCustomization(material).buttonPalette || "material"
    }

    function buttonPaletteColor(material, role) {
        return buttonColorRoles.includes(role) ? materialCustomization(material).buttonColors?.[role] || "" : ""
    }

    function setMaterialColor(material, role, color) {
        if (!materialColorRoles.includes(role))
            return
        setMaterialCustomization(material, Object.assign({}, materialCustomization(material), {[role]: color}))
    }

    function resetMaterialColors(material) {
        const colors = Object.assign({}, materialCustomization(material))
        materialColorRoles.forEach(role => delete colors[role])
        setMaterialCustomization(material, colors)
    }

    function setButtonPalette(material, palette) {
        setMaterialCustomization(material, Object.assign({}, materialCustomization(material), {buttonPalette: palette}))
    }

    function setButtonPaletteColor(material, role, color) {
        if (!buttonColorRoles.includes(role))
            return
        const colors = materialCustomization(material)
        const buttons = Object.assign({}, colors.buttonColors, {[role]: color})
        setMaterialCustomization(material, Object.assign({}, colors, {buttonColors: buttons}))
    }

    function resetButtonPalette(material) {
        const colors = Object.assign({}, materialCustomization(material))
        delete colors.buttonPalette
        delete colors.buttonColors
        setMaterialCustomization(material, colors)
    }

    function setMaterialCustomization(material, options) {
        if (!MaterialTheme.hasMaterial(material))
            return
        const all = Object.assign({}, preferences.materialCustomizations)
        const sanitized = validMaterialCustomization(options)
        if (Object.keys(sanitized).length)
            all[material] = sanitized
        else
            delete all[material]
        set("materialCustomizations", all)
    }

    function validMaterialCustomization(value) {
        const colors = {}
        if (!value || typeof value !== "object")
            return colors
        materialColorRoles.forEach(function(role) {
            if (colorValid(value[role]))
                colors[role] = value[role].toLowerCase()
        })
        if (buttonPaletteIds.includes(value.buttonPalette) && value.buttonPalette !== "material")
            colors.buttonPalette = value.buttonPalette
        if (value.buttonColors && typeof value.buttonColors === "object") {
            const buttons = {}
            buttonColorRoles.forEach(function(role) {
                if (colorValid(value.buttonColors[role]))
                    buttons[role] = value.buttonColors[role].toLowerCase()
            })
            if (Object.keys(buttons).length)
                colors.buttonColors = buttons
        }
        return colors
    }

    function validMaterialCustomizations(value, fallback) {
        if (!value || typeof value !== "object" || Array.isArray(value))
            return fallback
        const all = {}
        Object.keys(value).slice(0, 96).filter(material => MaterialTheme.hasMaterial(material)).forEach(function(material) {
            const options = validMaterialCustomization(value[material])
            if (Object.keys(options).length)
                all[material] = options
        })
        return all
    }

    function background(target) {
        if (MaterialTheme.mdmAppearance)
            return {mode: "solid", media: "", color: MaterialTheme.palette.background}
        const prefix = target === "main" ? "main" : "details"
        return {
            mode: preferences[prefix + "Mode"],
            media: preferences[prefix + "Media"],
            color: preferences[prefix + "Color"]
        }
    }

    function fileUrl(path) {
        const value = String(path || "").replace(/\\/g, "/")
        if (value.startsWith("file:")) return String(engine.localMediaUrl(value))
        if (!/^(?:\/|[A-Za-z]:\/)/.test(value)) return ""
        const encoded = value.split("/").map((part, index) =>
            index === 0 && /^[A-Za-z]:$/.test(part) ? part : encodeURIComponent(part)).join("/")
        const url = encoded.startsWith("//") ? "file:" + encoded
            : encoded.startsWith("/") ? "file://" + encoded : "file:///" + encoded
        return String(engine.localMediaUrl(url))
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

    function indicatorAnimation(value, fallback) {
        return progressAnimationChoices.some(choice => choice.value === value) ? value : fallback
    }

    function indicatorLayout(value, fallback) {
        return progressLayoutChoices.some(choice => choice.value === value) ? value : fallback
    }

    function indicatorLighting(value, fallback) {
        return lightingChoices.some(choice => choice.value === value) ? value : fallback
    }

    function paletteFor(value, fallback) {
        if (value === "material") return value
        if (value === "neon") return "aurora"
        return typeof value === "string" && Object.prototype.hasOwnProperty.call(MaterialTheme.indicatorPalettes, value)
            ? value : fallback
    }

    function trackFinishFor(value, fallback) {
        return progressTrackFinishChoices.some(choice => choice.value === value) ? value : fallback
    }

    function trackColorFor(value, fallback) {
        if (typeof value !== "string")
            return fallback
        if (value === "material" || Object.prototype.hasOwnProperty.call(progressTrackTints, value))
            return value
        if (colorValid(value))
            return value.toLowerCase()
        if (value.startsWith("palette:")) {
            const id = paletteFor(value.slice(8), "")
            if (id && id !== "material")
                return "palette:" + id
        }
        return fallback
    }

    function trackColors(value) {
        if (Object.prototype.hasOwnProperty.call(progressTrackTints, value)) {
            const color = progressTrackTints[value].color
            return [color, color]
        }
        if (colorValid(value))
            return [value, value]
        if (typeof value === "string" && value.startsWith("palette:")) {
            const id = paletteFor(value.slice(8), "")
            if (id && id !== "material")
                return MaterialTheme.indicatorPalettes[id].colors
        }
        return []
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
            "mh-glass-indicator": MaterialTheme.effectiveProgressPalette,
            "mh-glass-connection-indicator": MaterialTheme.effectiveConnectionPalette,
            "mh-glass-graph-indicator": MaterialTheme.effectiveGraphPalette,
            "mh-glass-progress-shape": shape(progressShape),
            "mh-glass-progress-material": "liquid-glass",
            "mh-glass-track-finish": progressTrackFinish,
            "mh-glass-track-color": progressTrackColor,
            "mh-glass-connection-shape": shape(connectionShape),
            "mh-glass-connection-material": "liquid-glass",
            "mh-glass-graph-shape": graphShape,
            "mh-glass-qt-appearance": JSON.stringify(Object.assign({}, preferences, {
                tint: colorText(MaterialTheme.tintColor),
                colorTheme: MaterialTheme.colorTheme,
                mdmMode: MaterialTheme.mdmMode,
                forcedAccent: MaterialTheme.forcedAccent,
                reducedMotion: MaterialTheme.reducedMotion,
                progressPalette: MaterialTheme.progressPalette,
                connectionPalette: MaterialTheme.connectionPalette,
                graphPalette: MaterialTheme.graphPalette
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
        if (typeof value === "string" && MaterialTheme.hasMaterial(value))
            MaterialTheme.current = value
        else if (complete)
            MaterialTheme.current = MaterialTheme.defaultMaterial
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
        MaterialTheme.forcedAccent = optionalColor(saved.forcedAccent, complete ? "" : MaterialTheme.forcedAccent)
        MaterialTheme.mdmMode = validChoice(saved.mdmMode, ["system", "light", "dark"],
            complete ? "system" : MaterialTheme.mdmMode)
        MaterialTheme.progressPalette = paletteFor(saved.progressPalette,
            paletteFor(data["mh-glass-indicator"], complete ? "material" : MaterialTheme.progressPalette))
        MaterialTheme.connectionPalette = paletteFor(saved.connectionPalette,
            paletteFor(data["mh-glass-connection-indicator"], complete ? "material" : MaterialTheme.connectionPalette))
        MaterialTheme.graphPalette = paletteFor(saved.graphPalette,
            paletteFor(data["mh-glass-graph-indicator"], complete ? "material" : MaterialTheme.graphPalette))

        const original = complete ? defaults() : preferences
        const modes = ["desktop", "solid", "wallpaper"]
        preferences = {
            cornerRadius: Number.isInteger(saved.cornerRadius) && saved.cornerRadius >= 0 && saved.cornerRadius <= 40
                ? saved.cornerRadius : original.cornerRadius,
            cornerPlacement: validChoice(saved.cornerPlacement, ["square", "top", "bottom", "all"], original.cornerPlacement),
            mainMode: validChoice(saved.mainMode || data["mh-glass-back-main"], modes, original.mainMode),
            detailsMode: validChoice(saved.detailsMode || data["mh-glass-back-details"], modes, original.detailsMode),
            mainMedia: fileUrl(saved.mainMedia ?? data["mh-glass-wall-main"] ?? original.mainMedia),
            detailsMedia: fileUrl(saved.detailsMedia ?? data["mh-glass-wall-detail"] ?? original.detailsMedia),
            mainColor: optionalColor(saved.mainColor ?? data["mh-glass-solid-main"], original.mainColor),
            detailsColor: optionalColor(saved.detailsColor ?? data["mh-glass-solid-details"], original.detailsColor),
            progressShape: indicatorShape(saved.progressShape || data["mh-glass-progress-shape"], original.progressShape),
            progressLayout: indicatorLayout(saved.progressLayout, original.progressLayout),
            progressThickness: indicatorSize(saved.progressThickness, original.progressThickness),
            connectionBlockSize: indicatorSize(saved.connectionBlockSize, original.connectionBlockSize),
            materialCustomizations: validMaterialCustomizations(saved.materialCustomizations, original.materialCustomizations),
            progressAnimation: indicatorAnimation(saved.progressAnimation, original.progressAnimation),
            progressLighting: indicatorLighting(saved.progressLighting, original.progressLighting),
            customProgressFill: typeof saved.customProgressFill === "boolean" ? saved.customProgressFill : original.customProgressFill,
            progressTrackFinish: trackFinishFor(saved.progressTrackFinish ?? data["mh-glass-track-finish"], original.progressTrackFinish),
            progressTrackColor: trackColorFor(saved.progressTrackColor ?? data["mh-glass-track-color"], original.progressTrackColor),
            connectionShape: indicatorShape(saved.connectionShape || data["mh-glass-connection-shape"], original.connectionShape),
            connectionAnimation: indicatorAnimation(saved.connectionAnimation, original.connectionAnimation),
            connectionLighting: indicatorLighting(saved.connectionLighting, original.connectionLighting),
            graphMaterial: validChoice(saved.graphMaterial, ["default", "jelly", "frosted", "crystal", "satin", "pearl", "aurora-mesh", "carbon", "mercury"], original.graphMaterial),
            graphShape: validChoice(saved.graphShape || data["mh-glass-graph-shape"], ["area", "line", "bars"], original.graphShape),
            graphAnimation: indicatorAnimation(saved.graphAnimation, original.graphAnimation),
            graphLighting: indicatorLighting(saved.graphLighting, original.graphLighting)
        }
    }

    function exportTheme() {
        const profile = MaterialTheme.palette
        const material = MaterialTheme.current
        const builtIn = MaterialTheme.isMdmPreset(material) || ["brushed-glass", "frosted-water-351", "rose-pine", "window-glass", "oversimplified",
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
                highContrast: true, uiScale: 100, dim: 26, blur: 6, indicator: MaterialTheme.effectiveProgressPalette,
                connectionIndicator: MaterialTheme.effectiveConnectionPalette, graphIndicator: MaterialTheme.effectiveGraphPalette, progressMaterial: legacy["mh-glass-progress-material"],
                connectionMaterial: legacy["mh-glass-connection-material"], graphMaterial: "gradient",
                progressShape: legacy["mh-glass-progress-shape"], connectionShape: legacy["mh-glass-connection-shape"],
                graphShape: graphShape, trackFinish: progressTrackFinish,
                trackColor: progressTrackColor === "material" || colorValid(progressTrackColor) ? "ice" : progressTrackColor,
                connectionTrackFinish: "recessed", connectionTrackColor: "ice"
            },
            qt: {
                material: material, tint: colorText(MaterialTheme.tintColor), progressShape: progressShape,
                mdmMode: MaterialTheme.mdmMode,
                progressLayout: progressLayout, progressThickness: progressThickness,
                connectionBlockSize: connectionBlockSize, materialCustomization: materialCustomization(material),
                progressAnimation: progressAnimation, progressLighting: progressLighting,
                customProgressFill: customProgressFill,
                progressTrackFinish: progressTrackFinish, progressTrackColor: progressTrackColor,
                connectionShape: connectionShape, connectionAnimation: connectionAnimation, connectionLighting: connectionLighting,
                graphMaterial: graphMaterial, graphAnimation: graphAnimation, graphLighting: graphLighting,
                reducedMotion: MaterialTheme.reducedMotion,
                forcedAccent: MaterialTheme.forcedAccent, colorTheme: MaterialTheme.colorTheme,
                progressPalette: MaterialTheme.progressPalette, connectionPalette: MaterialTheme.connectionPalette,
                graphPalette: MaterialTheme.graphPalette
            }
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
        if (!MaterialTheme.hasMaterial(material)) return false
        MaterialTheme.current = material
        MaterialTheme.mdmMode = validChoice(value.qt?.mdmMode, ["system", "light", "dark"], MaterialTheme.mdmMode)
        MaterialTheme.colorTheme = value.qt?.colorTheme === null ? null
            : validPalette(value.qt?.colorTheme) ? value.qt.colorTheme : value.palette
        MaterialTheme.translucency = typeof options.glassTranslucency === "number" ? options.glassTranslucency / 100 : -1
        MaterialTheme.tintStrength = options.tintStrength / 65
        if (colorValid(tint)) MaterialTheme.tintColor = tint
        if (value.qt && typeof value.qt.reducedMotion === "boolean") MaterialTheme.reducedMotion = value.qt.reducedMotion
        MaterialTheme.forcedAccent = optionalColor(value.qt?.forcedAccent, "")
        MaterialTheme.progressPalette = paletteFor(value.qt?.progressPalette,
            paletteFor(options.indicator, MaterialTheme.progressPalette))
        MaterialTheme.connectionPalette = paletteFor(value.qt?.connectionPalette,
            paletteFor(options.connectionIndicator, MaterialTheme.connectionPalette))
        MaterialTheme.graphPalette = paletteFor(value.qt?.graphPalette,
            paletteFor(options.graphIndicator, MaterialTheme.graphPalette))
        preferences = Object.assign({}, preferences, {
            progressShape: indicatorShape(value.qt?.progressShape || options.progressShape, progressShape),
            progressLayout: indicatorLayout(value.qt?.progressLayout, progressLayout),
            progressThickness: indicatorSize(value.qt?.progressThickness, progressThickness),
            connectionBlockSize: indicatorSize(value.qt?.connectionBlockSize, connectionBlockSize),
            progressAnimation: indicatorAnimation(value.qt?.progressAnimation, progressAnimation),
            progressLighting: indicatorLighting(value.qt?.progressLighting, progressLighting),
            customProgressFill: typeof value.qt?.customProgressFill === "boolean" ? value.qt.customProgressFill : customProgressFill,
            // Older Qt exports used placeholder values for the legacy backdrop fields.
            progressTrackFinish: trackFinishFor(value.qt ? value.qt.progressTrackFinish : options.trackFinish, progressTrackFinish),
            progressTrackColor: trackColorFor(value.qt ? value.qt.progressTrackColor : options.trackColor, progressTrackColor),
            connectionShape: indicatorShape(value.qt?.connectionShape || options.connectionShape, connectionShape),
            connectionAnimation: indicatorAnimation(value.qt?.connectionAnimation, connectionAnimation),
            connectionLighting: indicatorLighting(value.qt?.connectionLighting, connectionLighting),
            graphMaterial: validChoice(value.qt?.graphMaterial, ["default", "jelly", "frosted", "crystal", "satin", "pearl", "aurora-mesh", "carbon", "mercury"], graphMaterial),
            graphShape: validChoice(options.graphShape, ["area", "line", "bars"], graphShape),
            graphAnimation: indicatorAnimation(value.qt?.graphAnimation, graphAnimation),
            graphLighting: indicatorLighting(value.qt?.graphLighting, graphLighting)
        })
        if (value.qt && Object.prototype.hasOwnProperty.call(value.qt, "materialCustomization"))
            setMaterialCustomization(material, value.qt.materialCustomization)
        return true
    }
}
