.pragma library

function dimension(value, fallback) {
    const number = Number(value)
    return Number.isFinite(number) && number > 0 ? Math.round(number) : fallback
}

function read(settings, widthKey, heightKey, fallback) {
    return Qt.size(dimension(settings.value(widthKey, fallback.width), fallback.width),
                   dimension(settings.value(heightKey, fallback.height), fallback.height))
}

function record(settings, widthKey, heightKey, previousSize, currentSize, edges, saveHeight = true) {
    const widthChanged = (edges & (Qt.LeftEdge | Qt.RightEdge))
        && currentSize.width > 0 && currentSize.width !== previousSize.width
    const heightChanged = saveHeight && (edges & (Qt.TopEdge | Qt.BottomEdge))
        && currentSize.height > 0 && currentSize.height !== previousSize.height
    if (widthChanged)
        settings.setValue(widthKey, currentSize.width)
    if (heightChanged)
        settings.setValue(heightKey, currentSize.height)
    if (widthChanged || heightChanged)
        settings.sync()
}

function available(window, backend) {
    return backend?.windowWorkAreaSize
        ? backend.windowWorkAreaSize(window)
        : Qt.size(window.screen?.width ?? 0, window.screen?.height ?? 0)
}

function fit(requestedSize, minimumSize, availableSize) {
    const width = availableSize.width > 0 ? Math.min(requestedSize.width, availableSize.width) : requestedSize.width
    const height = availableSize.height > 0 ? Math.min(requestedSize.height, availableSize.height) : requestedSize.height
    return Qt.size(Math.max(minimumSize.width, width), Math.max(minimumSize.height, height))
}
