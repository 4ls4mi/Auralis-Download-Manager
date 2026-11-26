#pragma once
#include <QVariantMap>

namespace StoreStartup {
QVariantMap settings();
QVariantMap save(const QVariantMap &command);
}
