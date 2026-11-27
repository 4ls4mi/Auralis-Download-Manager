.pragma library

var fracture = [[.15, -.65], [.30, .84], [.45, .15], [.58, -.9], [.73, .73], [.87, -.38]];

function point(x, y) {
    return Qt.point(Number(x.toFixed(2)), Number(y.toFixed(2)));
}

function validCuts(requested, width, height) {
    var result = [];
    var rightmost = 0;
    for (var cut of (requested || []).slice().sort((a, b) => a.x - b.x)) {
        if (!Number.isFinite(cut.x) || !Number.isFinite(cut.slant) || !Number.isFinite(cut.gap))
            continue;
        var slope = cut.slant / height;
        var reach = Math.sqrt(1 + slope * slope);
        var half = reach * Math.max(5, cut.gap) * .5;
        var amplitude = Math.min(6, height * .092);
        var extent = Math.abs(cut.slant) * .5 + half + amplitude;
        if (cut.x - extent < rightmost + 30 || cut.x + extent > width - 30)
            continue;
        result.push({x: cut.x, slant: cut.slant, half: half, reach: reach, amplitude: amplitude});
        rightmost = cut.x + extent;
    }
    return result;
}

function cutX(cut, y, height, side, inset, notch) {
    return cut.x + cut.slant * (y / height - .5)
        + side * (cut.half + inset * cut.reach) + notch * cut.amplitude;
}

function rounded(points, sample) {
    var path = "";
    var vertices = [];
    for (var index = 0; index < points.length; ++index) {
        var previous = points[(index + points.length - 1) % points.length];
        var corner = points[index];
        var next = points[(index + 1) % points.length];
        var incoming = Math.min(.25, 2.1 / Math.max(1, Math.hypot(previous.x - corner.x, previous.y - corner.y)));
        var outgoing = Math.min(.25, 2.1 / Math.max(1, Math.hypot(next.x - corner.x, next.y - corner.y)));
        var first = point(corner.x + (previous.x - corner.x) * incoming,
                          corner.y + (previous.y - corner.y) * incoming);
        var last = point(corner.x + (next.x - corner.x) * outgoing,
                         corner.y + (next.y - corner.y) * outgoing);
        path += (index ? " L " : "M ") + first.x + " " + first.y
            + " Q " + corner.x + " " + corner.y + " " + last.x + " " + last.y;
        if (!sample)
            continue;
        vertices.push(first);
        for (var step = 1; step <= 4; ++step) {
            var u = step / 4;
            var v = 1 - u;
            vertices.push(point(v * v * first.x + 2 * u * v * corner.x + u * u * last.x,
                                v * v * first.y + 2 * u * v * corner.y + u * u * last.y));
        }
    }
    return {path: path + " Z", vertices: vertices};
}

function outline(width, height, left, right, edge, inset, sample) {
    var border = .65 + inset;
    var top = border;
    var bottom = height - border;
    var leftX = y => left ? cutX(left, y, height, 1, inset, 0) : border;
    var rightX = y => right ? cutX(right, y, height, -1, inset, 0) : width - border;
    var wave = Math.min(height * .083, edge === "menu" ? 2.4 : 4.1);
    var points = [];
    function horizontal(leading, trailing, y, direction, depths) {
        for (var index = 0; index < depths.length; ++index) {
            var [step, offset] = depths[index];
            points.push(point(leading + (trailing - leading) * step, y + direction * offset * wave));
        }
    }
    horizontal(leftX(top), rightX(top), top, 1, [[0,0],[.17,.38],[.29,.23],[.41,.77],[.57,.16],[.75,.47],[.91,.10],[1,0]]);
    for (var [fraction, notch] of fracture) {
        var y = top + (bottom - top) * fraction;
        points.push(point(right ? cutX(right, y, height, -1, inset, notch)
                                : width - border - wave * (1 - notch) * .48, y));
    }
    horizontal(rightX(bottom), leftX(bottom), bottom, -1, [[0,0],[.12,.50],[.27,.12],[.39,.66],[.48,.20],[.67,.78],[.8,.24],[1,0]]);
    for (var index = fracture.length - 1; index >= 0; --index) {
        var [fraction, notch] = fracture[index];
        var y = top + (bottom - top) * fraction;
        points.push(point(left ? cutX(left, y, height, 1, inset, notch)
                               : border + wave * (1 + notch) * .48, y));
    }
    return rounded(points, sample);
}

function shards(width, height, requested, edge) {
    if (width < 6 || height < 6)
        return [];
    var cuts = validCuts(requested, width, height);
    var output = [];
    for (var index = 0; index <= cuts.length; ++index) {
        var left = cuts[index - 1];
        var right = cuts[index];
        var shape = outline(width, height, left, right, edge, 0, true);
        var inner = outline(width, height, left, right, edge, 1.15, false);
        output.push({path: shape.path, vertices: shape.vertices, bevel: shape.path + " " + inner.path});
    }
    return output;
}
