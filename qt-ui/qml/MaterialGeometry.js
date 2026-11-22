.pragma library

function frame(x, y, width, height, radius, style) {
    if (width <= 0 || height <= 0)
        return "";
    const r = Math.max(0, Math.min(radius, width / 2, height / 2));
    const right = x + width;
    const bottom = y + height;
    if (style === "square" || r === 0)
        return `M ${x} ${y} H ${right} V ${bottom} H ${x} Z`;

    const chamfered = ["chamfer", "ice", "prism"].includes(style);
    if (chamfered) {
        const corners = cutCorners(width, height, r, style);
        const tl = corners.topLeft;
        const tr = corners.topRight;
        const br = corners.bottomRight;
        const bl = corners.bottomLeft;
        return `M ${x + tl} ${y} H ${right - tr} L ${right} ${y + tr}
                V ${bottom - br} L ${right - br} ${bottom}
                H ${x + bl} L ${x} ${bottom - bl} V ${y + tl} Z`;
    }

    if (style === "bubble") {
        const bulge = Math.min(height * .09, r * .42);
        return `M ${x + r} ${y + bulge}
                C ${x + width * .20} ${y - bulge} ${x + width * .34} ${y + bulge * 2} ${x + width * .50} ${y + bulge}
                S ${x + width * .78} ${y - bulge * .5} ${right - r} ${y + bulge}
                Q ${right} ${y} ${right} ${y + r} V ${bottom - r}
                Q ${right} ${bottom} ${right - r} ${bottom - bulge}
                C ${x + width * .78} ${bottom + bulge * .5} ${x + width * .67} ${bottom - bulge * 2} ${x + width * .50} ${bottom - bulge}
                S ${x + width * .20} ${bottom + bulge} ${x + r} ${bottom - bulge}
                Q ${x} ${bottom} ${x} ${bottom - r} V ${y + r}
                Q ${x} ${y} ${x + r} ${y + bulge} Z`;
    }

    const small = style === "smoke" || style === "frost" ? r * .36 : r;
    return `M ${x + r} ${y} H ${right - small} Q ${right} ${y} ${right} ${y + small}
            V ${bottom - r} Q ${right} ${bottom} ${right - r} ${bottom}
            H ${x + small} Q ${x} ${bottom} ${x} ${bottom - small}
            V ${y + r} Q ${x} ${y} ${x + r} ${y} Z`;
}

function cutCorners(width, height, radius, style) {
    const cut = Math.max(0, Math.min(radius, width * .41, height * .49));
    return {
        topLeft: style === "ice" ? cut * .45 : cut,
        topRight: style === "prism" ? cut * 1.3 : cut,
        bottomRight: style === "chamfer" ? cut : cut * .58,
        bottomLeft: style === "ice" ? cut : cut * .62
    };
}

function facet(width, height, radius, style, upper) {
    if (width <= 20 || height <= 14)
        return "";
    const corners = cutCorners(width - 1.2, height - 1.2, radius, style);
    const cut = upper ? corners.topRight : corners.bottomLeft;
    const reach = Math.min(width * .46, cut * 4.5);
    if (upper)
        return `M ${width - reach} 1.2 H ${width - cut - 1.2} L ${width - 1.2} ${cut + 1.2}
                L ${width - reach * .54} ${cut * .58 + 1.2} Z`;
    return `M 1.2 ${height - cut - 1.2} L ${reach * .58} ${height - cut * .52 - 1.2}
            L ${reach} ${height - 1.2} H ${cut + 1.2} Z`;
}

function barEdge(x, width, height, shape) {
    const cap = Math.min(height * .47, width * .28);
    const end = Math.min(x, width - x);
    const aspect = (end - cap) / Math.max(.01, cap);
    if (shape === "prism" || shape === "ice" || shape === "chamfer")
        return end < cap ? height * .36 * (1 - end / cap) : 0;
    if (shape === "square" || shape === "plain")
        return 0;
    if (end < cap)
        return height * .5 * (1 - Math.sqrt(Math.max(0, 1 - aspect * aspect)));
    if (shape !== "bubble")
        return 0;
    const phase = (x - cap) / Math.max(.01, width - 2 * cap);
    const chambers = Math.max(1, Math.min(3, Math.floor(width / (3.2 * height))));
    return height * .24 * Math.pow(Math.sin(Math.PI * chambers * phase), 2);
}

function barContour(width, height, shape, amount, phase) {
    if (width <= 0 || height <= 0 || amount <= 0)
        return "";
    const cut = width * Math.min(1, amount);
    const lip = amount < 1
        ? Math.min(cut * .32, height * (shape === "bubble" ? .17 : .12), width - cut)
        : 0;
    const last = cut - lip;
    const steps = Math.max(10, Math.min(80, Math.ceil(last / Math.max(1, height * .28))));
    const positions = Array.from({ length: steps + 1 }, (_, index) => last * index / steps);
    const faceted = ["prism", "ice", "chamfer", "square", "plain"].includes(shape);
    const cap = Math.min(height * .47, width * .28);
    for (const fraction of faceted ? [1] : [.01, .03, .08, .18, .36, .58, .8, 1]) {
        const point = fraction * cap;
        if (point < last)
            positions.push(point);
        if (width - point < last)
            positions.push(width - point);
    }
    positions.sort((left, right) => left - right);
    const samples = positions.filter((point, index) => index === 0 || point - positions[index - 1] > .0001);
    if (samples[samples.length - 1] !== last)
        samples.push(last);
    const top = `M 0 ${barEdge(0, width, height, shape)}` + traceBarEdge(samples, width, height, shape, false, !faceted);
    const bottom = traceBarEdge(samples.reverse(), width, height, shape, true, !faceted);
    const endY = barEdge(last, width, height, shape);
    const turn = lip > 0
        ? ` C ${cut + lip * .35 * Math.sin(phase)} ${endY + height * .17}
               ${cut - lip * .35 * Math.sin(phase)} ${height - endY - height * .17} ${last} ${height - endY}`
        : ` L ${last} ${height - endY}`;
    return top + turn + bottom + " Z";
}

function traceBarEdge(samples, width, height, shape, lower, smooth) {
    let path = "";
    const y = x => lower ? height - barEdge(x, width, height, shape) : barEdge(x, width, height, shape);
    for (let index = 1; index < samples.length; ++index) {
        const x = samples[index];
        if (smooth && index < samples.length - 1) {
            const next = samples[index + 1];
            path += ` Q ${x} ${y(x)} ${(x + next) / 2} ${(y(x) + y(next)) / 2}`;
        } else {
            path += ` L ${x} ${y(x)}`;
        }
    }
    return path;
}

function barHighlights(width, height, shape, lower) {
    if (width <= 0 || height <= 0)
        return "";
    const inset = Math.max(1, height * .11);
    const cap = Math.min(height * .47, width * .28);
    const chambers = shape === "bubble" ? Math.max(1, Math.min(3, Math.floor(width / (3.2 * height)))) : 1;
    const span = width - cap * 2;
    let path = "";
    for (let index = 0; index <= chambers; ++index) {
        const center = cap + span * index / chambers;
        const start = Math.max(inset, center - Math.min(height * .4, span / (4 * chambers)));
        const end = Math.min(width - inset, center + Math.min(height * 1.2, span / (4 * chambers)));
        const sign = lower ? -1 : 1;
        const origin = lower ? height : 0;
        path += ` M ${start} ${origin + sign * (barEdge(start, width, height, shape) + inset)}
                  Q ${center} ${origin + sign * inset} ${end} ${origin + sign * (barEdge(end, width, height, shape) + inset)}`;
    }
    return path;
}
