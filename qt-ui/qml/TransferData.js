.pragma library

function find(rows, id) {
    if (rows && id !== null && id !== undefined) {
        for (let row of rows) {
            if (String(row.id) === String(id))
                return row
        }
    }
    return null
}

function bytes(number) {
    if (number === null || number === undefined || !isFinite(Number(number)))
        return "—"
    const units = ["B", "KB", "MB", "GB", "TB", "PB"]
    let value = Math.max(0, Number(number))
    let unit = 0
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024
        unit++
    }
    return value.toFixed(unit === 0 ? 0 : 1) + " " + units[unit]
}

function rate(number) {
    return number === null || number === undefined ? "—" : bytes(number) + "/s"
}

function timeLeft(item) {
    if (!item || item.status !== "Downloading" || !(item.size > 0) || !(item.speed > 0))
        return "—"
    const seconds = Math.ceil(Math.max(0, item.size - item.downloaded) / item.speed)
    if (seconds < 60)
        return seconds + "s"
    if (seconds < 3600)
        return Math.floor(seconds / 60) + "m " + (seconds % 60) + "s"
    return Math.floor(seconds / 3600) + "h " + Math.floor((seconds % 3600) / 60) + "m"
}

function fraction(item) {
    if (!item)
        return 0
    if (item.status === "Complete")
        return 1
    return item.size > 0 ? Math.max(0, Math.min(1, item.downloaded / item.size)) : 0
}

function problem(reply, error) {
    const message = error ? String(error) : reply && reply.error ? String(reply.error) : ""
    return message ? qsTranslate("BackendErrors", message) : ""
}

function statusLabel(state) {
    switch (state) {
    case "Queued": return qsTranslate("Main", "Queued")
    case "Downloading": return qsTranslate("Main", "Downloading")
    case "Stopped": return qsTranslate("Main", "Paused")
    case "Complete": return qsTranslate("Main", "Completed")
    case "Error": return qsTranslate("Main", "Failed")
    default: return state || "—"
    }
}

function connectionLabel(state) {
    switch (state) {
    case "Connecting": return qsTranslate("DownloadWindow", "Connecting")
    case "Receiving": return qsTranslate("DownloadWindow", "Receiving")
    case "Retrying": return qsTranslate("DownloadWindow", "Retrying")
    case "Finished": return qsTranslate("DownloadWindow", "Finished")
    case "Failed": return qsTranslate("Main", "Failed")
    case "Retired": return qsTranslate("DownloadWindow", "Retired")
    default: return qsTranslate("DownloadWindow", "Unknown")
    }
}

function assigned(id, segments, includeLastOwner = false) {
    if (id === null || id === undefined)
        return null
    let total = 0
    let saved = 0
    for (let piece of segments || []) {
        const owner = piece.worker ?? (includeLastOwner ? piece.last_worker : null)
        if (owner === null || owner === undefined || Number(owner) !== Number(id))
            continue
        total += Math.max(0, piece.end - piece.start)
        saved += Math.min(Math.max(0, piece.cursor - piece.start), Math.max(0, piece.end - piece.start))
    }
    return total > 0 ? saved / total : null
}
