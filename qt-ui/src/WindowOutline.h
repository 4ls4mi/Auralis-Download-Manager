#pragma once

#include <QtGlobal>

class QImage;
class QPoint;
class QPolygonF;
class QRectF;
class QSize;
class QSizeF;
class QWindow;

namespace WindowOutline {
bool configureAntialiasing(QWindow *window, const QSizeF &reach, int corners = 15);
QPolygonF framePolygon(const QRectF &frame, const QSizeF &reach, int corners, qreal fringe = 0);
QImage blurShadowMask(QImage mask, qreal scale, int padding, const QPoint &offset, int strength);
QImage shadowImage(const QSize &framePixels, const QSizeF &reachPixels, int corners, qreal scale, int padding);
}
