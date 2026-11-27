.pragma library

const catalog = {
    "classic": {
        "label": "Classic",
        "motions": [
            {
                "value": "classic",
                "label": "Polished sweep"
            },
            {
                "value": "water",
                "label": "Gushing water"
            },
            {
                "value": "jelly",
                "label": "Elastic glass"
            }
        ]
    },
    "status-track": {
        "label": "Status track",
        "motions": [
            {
                "value": "status-breathe",
                "label": "Status breathing"
            },
            {
                "value": "status-signal",
                "label": "Leading signal"
            },
            {
                "value": "status-scan",
                "label": "Status scan"
            }
        ]
    },
    "pill-segments": {
        "label": "Pill segments",
        "motions": [
            {
                "value": "pill-cascade",
                "label": "Pill cascade"
            },
            {
                "value": "pill-wave",
                "label": "Pill wave"
            },
            {
                "value": "pill-squeeze",
                "label": "Pill compression"
            }
        ]
    },
    "thin-line": {
        "label": "Thin line",
        "motions": [
            {
                "value": "line-comet",
                "label": "Line comet"
            },
            {
                "value": "line-packets",
                "label": "Line packets"
            },
            {
                "value": "line-breathe",
                "label": "Line breathing"
            }
        ]
    },
    "striped-fill": {
        "label": "Striped fill",
        "motions": [
            {
                "value": "stripe-march",
                "label": "Forward stripes"
            },
            {
                "value": "stripe-reverse",
                "label": "Reverse stripes"
            },
            {
                "value": "stripe-pulse",
                "label": "Stripe pulse"
            }
        ]
    },
    "liquid-silk": {
        "label": "Liquid silk",
        "motions": [
            {
                "value": "silk-laminar",
                "label": "Laminar flow"
            },
            {
                "value": "silk-ripples",
                "label": "Surface ripples"
            },
            {
                "value": "silk-undertow",
                "label": "Slow undertow"
            }
        ]
    },
    "elastic-gel": {
        "label": "Elastic gel",
        "motions": [
            {
                "value": "gel-compress",
                "label": "Rolling compression"
            },
            {
                "value": "gel-wobble",
                "label": "Soft wobble"
            },
            {
                "value": "gel-spring",
                "label": "Spring wave"
            }
        ]
    },
    "photon-streams": {
        "label": "Photon streams",
        "motions": [
            {
                "value": "photon-streaks",
                "label": "Fast streaks"
            },
            {
                "value": "photon-alternate",
                "label": "Alternating streams"
            },
            {
                "value": "photon-bursts",
                "label": "Packet bursts"
            }
        ]
    },
    "crystal-shimmer": {
        "label": "Crystal shimmer",
        "motions": [
            {
                "value": "crystal-sweep",
                "label": "Facet sweep"
            },
            {
                "value": "crystal-flash",
                "label": "Staggered flash"
            },
            {
                "value": "crystal-refract",
                "label": "Traveling refraction"
            }
        ]
    },
    "capillary-current": {
        "label": "Capillary current",
        "motions": [
            {
                "value": "capillary-branch",
                "label": "Branching current"
            },
            {
                "value": "capillary-wave",
                "label": "Wave cascade"
            },
            {
                "value": "capillary-charge",
                "label": "Synchronized charge"
            }
        ]
    },
    "vortex-glass": {
        "label": "Vortex glass",
        "motions": [
            {
                "value": "vortex-eddies",
                "label": "Rolling eddies"
            },
            {
                "value": "vortex-twin",
                "label": "Twin vortices"
            },
            {
                "value": "vortex-sparks",
                "label": "Orbiting sparks"
            }
        ]
    }
}

function layout(value) { return Object.prototype.hasOwnProperty.call(catalog,value) ? value : "classic" }
function layouts() { return Object.keys(catalog).map(value => ({value: value,label: catalog[value].label})) }
function artistic(value) { return ["liquid-silk","elastic-gel","photon-streams","crystal-shimmer","capillary-current","vortex-glass"].includes(value) }
function choices(value) { return catalog[layout(value)].motions.concat([{value:"none",label:"No motion"}]) }
function normalize(value, motion, fallback) {
    const options=choices(value)
    if(options.some(option=>option.value===motion)) return motion
    // Migrate the previous global choices to an effect belonging to this layout.
    const legacy=["classic","water","jelly","sheen","heartbeat","tide","elastic","glints","current"]
    if(legacy.includes(motion)) {
        const index=["water","tide","current"].includes(motion)?1:["jelly","elastic","glints"].includes(motion)?2:0
        return options[index].value
    }
    return options.some(option=>option.value===fallback)?fallback:options[0].value
}
function modeIndex(value,motion) { return Math.max(0,catalog[layout(value)].motions.findIndex(option=>option.value===normalize(value,motion))) }
function remembered(saved) {
    const result={}
    if(saved && typeof saved==="object" && !Array.isArray(saved))
        for(const key of Object.keys(catalog)) if(typeof saved[key]==="string") result[key]=normalize(key,saved[key])
    return result
}
