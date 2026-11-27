.pragma library
.import "MaterialGeometry.js" as Geometry

function style(name) {
    switch (name) {
    case "status-track":
    case "pill-segments":
    case "thin-line":
    case "striped-fill":
        return name
    default:
        return "classic"
    }
}

function trackHeight(available, layout, scale = 1) {
    switch (layout) {
    case "thin-line": return Math.min(5 * scale, available)
    case "pill-segments": return available * .77
    case "status-track": return available * .94
    default: return available
    }
}

function gap(width, height, layout) {
    return layout === "pill-segments" ? Math.min(8, height * .48, width / 16) : 0
}

function spans(width, height, layout, fraction) {
    if (width <= 0 || height <= 0 || fraction <= 0)
        return []
    if (layout !== "pill-segments")
        return [{x: 0, width: width * Math.min(1, fraction)}]

    const clear = gap(width, height, layout)
    const segment = (width - 4 * clear) / 5
    const result = []
    for (let index = 0; index < 5; ++index) {
        // Each pill represents exactly one fifth of the received bytes.
        const partial = Math.max(0, Math.min(1, fraction * 5 - index))
        if (partial > 0)
            result.push({x: index * (segment + clear), width: segment * partial})
    }
    return result
}

function path(spans, height, layout, shape = "round") {
    const radius = layout === "pill-segments" || layout === "thin-line"
        ? height / 2 : Math.min(6, height * .28)
    return spans.map(span => Geometry.frame(span.x, 0, span.width, height, radius, shape === "plain" ? "square" : shape)).join(" ")
}

function highlights(spans, height, lower) {
    if (height < 6)
        return ""
    const y = height * (lower ? .88 : .12)
    return spans.filter(span => span.width >= height * 1.4).map(span => {
        const start = span.x + height * .37
        const end = Math.min(span.x + span.width - height * .32, start + height * 2.1)
        return `M ${start} ${y} H ${end}`
    }).join(" ")
}
