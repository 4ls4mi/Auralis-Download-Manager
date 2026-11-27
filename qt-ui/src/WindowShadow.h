#pragma once

#include <QtGlobal>

class QRegion;
class QSize;
class QSizeF;
class QWindow;

namespace WindowShadow {
void clearFrame(QWindow *owner);
void clearPanels(QWindow *owner);
void update(QWindow *owner, const QSizeF &reach, int corners);
void updatePanels(QWindow *owner, const QSize &framePixels, const QRegion &panels, qreal scale);
}
