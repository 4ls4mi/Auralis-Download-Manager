#pragma once

#include <functional>

class QSize;
class QWindow;

namespace FrameResize {
void install(QWindow *window, int borderSize, int cornerSize);
void observeNative(QWindow *window, std::function<void(const QSize &, const QSize &, int)> finished);
}
