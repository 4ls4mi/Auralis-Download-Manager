#pragma once

class QSizeF;
class QWindow;

namespace WindowShadow {
void update(QWindow *owner, const QSizeF &reach, int corners);
}
