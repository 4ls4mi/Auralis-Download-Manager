#include "BrowserSetup.h"

#ifdef Q_OS_WIN
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

#include <windows.h>
#include <shlwapi.h>
#include <vector>

namespace {
const auto StoreId = QStringLiteral("bobmhloppnfipdjjncalidjenegfgebg");
const auto StoreUpdate = QStringLiteral("https://clients2.google.com/service/update2/crx");
const auto SettingsName = QStringLiteral("ExtensionSettings");
const auto InstallationMode = QStringLiteral("installation_mode");
const auto UpdateUrl = QStringLiteral("update_url");
const auto NormalInstalled = QStringLiteral("normal_installed");
const auto NativeHost = QStringLiteral("com.misterdownloadmanager.host");

QJsonObject auralisPolicy()
{
    return {{InstallationMode, NormalInstalled}, {UpdateUrl, StoreUpdate}};
}

QString ownershipKey(const QString &browserId)
{
    return QStringLiteral("BrowserIntegration/managedExtension/") + browserId;
}

QString queryHttpsAssociation(ASSOCSTR type)
{
    const auto flags = static_cast<ASSOCF>(ASSOCF_IS_PROTOCOL | ASSOCF_INIT_IGNOREUNKNOWN | ASSOCF_NOTRUNCATE);
    DWORD length = 0;
    if (AssocQueryStringW(flags, type, L"https", nullptr, nullptr, &length) != S_FALSE
        || length < 2 || length > 32768)
        return {};
    std::vector<wchar_t> value(length);
    if (AssocQueryStringW(flags, type, L"https", nullptr, value.data(), &length) != S_OK)
        return {};
    return QString::fromWCharArray(value.data());
}

QString policyPath(const QString &browserId)
{
    if (browserId == QStringLiteral("chrome"))
        return QStringLiteral("\\SOFTWARE\\Policies\\Google\\Chrome");
    if (browserId == QStringLiteral("edge"))
        return QStringLiteral("\\SOFTWARE\\Policies\\Microsoft\\Edge");
    return {};
}

bool listContains(QSettings &registry, const QString &key, const QString &value, bool wildcard)
{
    registry.beginGroup(key);
    bool found = false;
    for (const auto &entry : registry.childKeys()) {
        const auto item = registry.value(entry).toString().section(QLatin1Char(';'), 0, 0).trimmed();
        if (item == value || (wildcard && item == QStringLiteral("*"))) {
            found = true;
            break;
        }
    }
    registry.endGroup();
    return found;
}

bool existingPolicyBlocksSetup(QSettings &registry)
{
    const auto external = QStringLiteral("BlockExternalExtensions");
    const auto native = QStringLiteral("NativeMessagingUserLevelHosts");
    const auto allowedTypes = QStringLiteral("ExtensionAllowedTypes");
    return registry.value(external).toBool()
        || (registry.contains(native) && !registry.value(native).toBool())
        || (registry.childGroups().contains(allowedTypes, Qt::CaseInsensitive)
            && !listContains(registry, allowedTypes, QStringLiteral("extension"), false))
        || listContains(registry, QStringLiteral("ExtensionInstallBlocklist"), StoreId, true)
        || listContains(registry, QStringLiteral("ExtensionInstallBlacklist"), StoreId, true)
        || listContains(registry, QStringLiteral("ExtensionInstallForcelist"), StoreId, false)
        || listContains(registry, QStringLiteral("NativeMessagingBlocklist"), NativeHost, true);
}

struct Review {
    BrowserSetup::PolicyStatus status;
    QJsonObject policy;
};

Review reviewPolicy(const QString &browserId, const QString &path, QSettings &user)
{
    const QString governed = QCoreApplication::translate("BrowserSetup",
        "Existing browser policies control extension installation. Use the browser’s supported setup or your administrator’s policy.");
    for (const auto format : {QSettings::Registry64Format, QSettings::Registry32Format}) {
        QSettings machine(QStringLiteral("HKEY_LOCAL_MACHINE") + path, format);
        if (machine.contains(SettingsName) || existingPolicyBlocksSetup(machine) || machine.status() != QSettings::NoError)
            return {{false, false, governed}, {}};
    }
    if (existingPolicyBlocksSetup(user) || user.status() != QSettings::NoError)
        return {{false, false, governed}, {}};

    QJsonObject settings;
    if (user.contains(SettingsName)) {
        const auto document = QJsonDocument::fromJson(user.value(SettingsName).toString().toUtf8());
        if (!document.isObject())
            return {{false, false, governed}, {}};
        settings = document.object();
    }

    const auto existing = settings.value(StoreId);
    const auto entry = existing.toObject();
    const auto mode = entry.value(InstallationMode).toString();
    const auto update = entry.value(UpdateUrl).toString();
    if ((mode == NormalInstalled || mode == QStringLiteral("force_installed")) && update == StoreUpdate) {
        QSettings ownership;
        const bool removable = entry == auralisPolicy() && ownership.contains(ownershipKey(browserId));
        return {{false, true, {}, removable}, settings};
    }

    // Adding a specific extension can change how a browser inherits wildcard permissions.
    // Leave any existing wildcard restrictions and store-level policy in full control.
    const auto global = settings.value(QStringLiteral("*"));
    const auto defaults = global.toObject();
    if ((!global.isUndefined() && !global.isObject())
        || (!defaults.isEmpty() && !(defaults.size() == 1
                && defaults.value(InstallationMode).toString() == QStringLiteral("allowed"))))
        return {{false, false, governed}, {}};
    for (auto it = settings.constBegin(); it != settings.constEnd(); ++it) {
        if (it.key().startsWith(QStringLiteral("update_url:"), Qt::CaseInsensitive))
            return {{false, false, governed}, {}};
    }
    if (!existing.isUndefined())
        return {{false, false, governed}, {}};
    return {{true, false, {}}, settings};
}
}

BrowserSetup::Handler BrowserSetup::defaultHttpsHandler()
{
    const QFileInfo path(queryHttpsAssociation(ASSOCSTR_EXECUTABLE));
    const auto executable = QDir::toNativeSeparators(path.canonicalFilePath());
    const bool localExecutable = executable.size() >= 3 && executable[0].isLetter()
        && executable[1] == QLatin1Char(':') && executable[2] == QLatin1Char('\\') && path.isFile();
    return {localExecutable ? executable : QString(), queryHttpsAssociation(ASSOCSTR_FRIENDLYAPPNAME)};
}

QUrl BrowserSetup::storeUrl()
{
    return QUrl(QStringLiteral("https://chromewebstore.google.com/detail/auralis-download-manager/") + StoreId);
}

QString BrowserSetup::extensionManager(const QString &browserId)
{
    return browserId == QStringLiteral("edge") ? QStringLiteral("edge://extensions/")
                                               : QStringLiteral("chrome://extensions/");
}

BrowserSetup::PolicyStatus BrowserSetup::policyStatus(const QString &browserId)
{
    const auto path = policyPath(browserId);
    if (path.isEmpty())
        return {};
    QSettings user(QStringLiteral("HKEY_CURRENT_USER") + path, QSettings::Registry64Format);
    return reviewPolicy(browserId, path, user).status;
}

QString BrowserSetup::installPolicy(const QString &browserId)
{
    const auto path = policyPath(browserId);
    if (path.isEmpty())
        return QCoreApplication::translate("BrowserSetup", "Managed setup is unavailable for this browser.");
    QSettings user(QStringLiteral("HKEY_CURRENT_USER") + path, QSettings::Registry64Format);
    auto review = reviewPolicy(browserId, path, user);
    if (review.status.configured || !review.status.available)
        return review.status.problem;
    const bool hadSettings = user.contains(SettingsName);
    review.policy.insert(StoreId, auralisPolicy());
    user.setValue(SettingsName, QString::fromUtf8(QJsonDocument(review.policy).toJson(QJsonDocument::Compact)));
    user.sync();
    if (user.status() != QSettings::NoError)
        return QCoreApplication::translate("BrowserSetup", "Could not save browser setup for the current Windows user.");
    QSettings ownership;
    ownership.setValue(ownershipKey(browserId), hadSettings);
    ownership.sync();
    return {};
}

QString BrowserSetup::removePolicy(const QString &browserId)
{
    const auto path = policyPath(browserId);
    if (path.isEmpty())
        return QCoreApplication::translate("BrowserSetup", "Managed setup is unavailable for this browser.");
    QSettings user(QStringLiteral("HKEY_CURRENT_USER") + path, QSettings::Registry64Format);
    auto review = reviewPolicy(browserId, path, user);
    if (!review.status.removable)
        return QCoreApplication::translate("BrowserSetup", "The existing browser policy was changed or was configured outside Auralis.");
    QSettings ownership;
    const auto key = ownershipKey(browserId);
    review.policy.remove(StoreId);
    if (review.policy.isEmpty() && !ownership.value(key).toBool())
        user.remove(SettingsName);
    else
        user.setValue(SettingsName, QString::fromUtf8(QJsonDocument(review.policy).toJson(QJsonDocument::Compact)));
    user.sync();
    if (user.status() != QSettings::NoError)
        return QCoreApplication::translate("BrowserSetup", "Could not remove browser setup for the current Windows user.");
    ownership.remove(key);
    return {};
}
#endif
