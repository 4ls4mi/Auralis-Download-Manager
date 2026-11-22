#pragma once

class QWindow;

namespace FrameResize {
void install(QWindow *window, int borderSize, int cornerSize);
}
