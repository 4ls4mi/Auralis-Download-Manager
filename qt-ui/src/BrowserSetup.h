#pragma once

#include <QString>
#include <QStringList>
#include <QUrl>

namespace BrowserSetup {
struct Handler {
    QString executable;
    QString name;
};

struct OfferStatus {
    bool available = false;
    bool registered = false;
    bool removable = false;
    QString problem;
};

struct NativeHostStatus {
    bool registered = false;
    bool canRegister = false;
    bool anotherApplication = false;
    QString problem;
};

QString validatedBrowserExecutable(const QString &path);
Handler defaultHttpsHandler();
QUrl storeUrl();
QStringList browserPolicyRefreshArguments(const QString &browserId, const QString &executable);
bool isInstalledApplication();
NativeHostStatus nativeHostStatus(const QString &browserId);
QString registerNativeHost(const QString &browserId, bool repair);
OfferStatus chromeOfferStatus();
QString registerChromeOffer();
QString removeChromeOffer();
bool legacyPolicyRemovable(const QString &browserId);
QString removeLegacyPolicy(const QString &browserId, bool *windowsApprovalRequired = nullptr);
QString removeLegacyChromePolicyWithAdministratorApproval();
}
