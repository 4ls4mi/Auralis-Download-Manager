.pragma library

const treatments = {
    polished: {halo: .80, haloWidth: .85, reflection: 1, depth: .42, caustic: 0, optic: 0},
    depth: {halo: .78, haloWidth: .92, reflection: .76, depth: 1, caustic: 0, optic: 0},
    caustics: {halo: .94, haloWidth: 1.04, reflection: .91, depth: .64, caustic: 1, optic: 0},
    halo: {halo: 1.42, haloWidth: 1.40, reflection: .87, depth: .48, caustic: 0, optic: 0},
    frost: {halo: .52, haloWidth: 1.18, reflection: .64, depth: .28, caustic: 0, optic: 1},
    chrome: {halo: .43, haloWidth: .76, reflection: .99, depth: .81, caustic: 0, optic: 2},
    underlit: {halo: .82, haloWidth: 1.02, reflection: .52, depth: .89, caustic: 0, optic: 3},
    smoke: {halo: .36, haloWidth: .78, reflection: .46, depth: .97, caustic: 0, optic: 4},
    satin: {halo: .55, haloWidth: 1.14, reflection: .67, depth: .43, caustic: 0, optic: 5},
    facets: {halo: .88, haloWidth: .81, reflection: .92, depth: .79, caustic: .44, optic: 6},
    cross: {halo: .62, haloWidth: .98, reflection: .91, depth: .67, caustic: .28, optic: 7},
    pinpoint: {halo: .56, haloWidth: .78, reflection: 1, depth: .53, caustic: 0, optic: 8},
    fluted: {halo: .89, haloWidth: .91, reflection: .78, depth: .68, caustic: .60, optic: 9},
    iridescent: {halo: 1.05, haloWidth: 1.12, reflection: .93, depth: .53, caustic: .25, optic: 10},
    backlit: {halo: .96, haloWidth: 1.18, reflection: .49, depth: .52, caustic: .31, optic: 11},
    "edge-lit": {halo: 1.14, haloWidth: 1.17, reflection: .94, depth: .71, caustic: .18, optic: 12}
}

const outletPosition = .59
const dropContact = .70

function style(name) {
    return Object.prototype.hasOwnProperty.call(treatments, name) ? treatments[name] : treatments.polished
}

function dropCycle(phase, slowPhase, index, animation) {
    const clock = animation === "jelly" ? slowPhase : phase
    const cycle = clock / (2 * Math.PI) * (animation === "water" ? 2 : 1) + index * .381966
    return cycle - Math.floor(cycle)
}
