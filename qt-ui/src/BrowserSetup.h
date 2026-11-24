#pragma once

#include <QString>
#include <QStringList>
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

struct NativeHostStatus {
    bool registered = false;
    bool canRegister = false;
    bool anotherApplication = false;
    QString problem;
};

Handler defaultHttpsHandler();
QUrl storeUrl();
QStringList browserPolicyRefreshArguments(const QString &browserId, const QString &executable);
bool isInstalledApplication();
NativeHostStatus nativeHostStatus(const QString &browserId);
QString registerNativeHost(const QString &browserId, bool repair);
PolicyStatus policyStatus(const QString &browserId);
QString installPolicy(const QString &browserId, bool *windowsApprovalRequired = nullptr);
QString removePolicy(const QString &browserId, bool *windowsApprovalRequired = nullptr);
bool chromeWindowsApprovalAvailable();
QString installChromePolicyWithAdministratorApproval(bool remove = false);
}
