#pragma once

#include <QVariant>

class QWindow;

namespace PanelBackdrop {
bool update(QWindow *window, const QVariantList &panels, bool enabled);
}
