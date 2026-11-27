pragma ComponentBehavior: Bound

import QtQuick
import "FracturedAcrylicGeometry.js" as Geometry

FracturedPanel {
    id: panel

    required property string shard

    readonly property var geometry: Geometry.shape(shard)
    edge: shard
    outlineOverride: ({path: geometry.outline, vertices: geometry.vertices, bevel: geometry.bevel})
}
