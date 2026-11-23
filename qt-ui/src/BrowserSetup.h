#pragma once

#include <QString>
#include <QUrl>

namespace BrowserSetup {
struct Handler {
    QString executable;
    QString name;
};

struct PolicyStatus {
    bool available = false;
    bool configured = false;
    QString problem;
    bool removable = false;
};

Handler defaultHttpsHandler();
QUrl storeUrl();
QString extensionManager(const QString &browserId);
PolicyStatus policyStatus(const QString &browserId);
QString installPolicy(const QString &browserId);
QString removePolicy(const QString &browserId);
}
