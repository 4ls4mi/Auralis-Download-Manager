#include "BrowserSetup.h"

#ifdef Q_OS_WIN
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSettings>
#include <QStringList>

#include <windows.h>
#include <shlwapi.h>
#include <array>
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

QString browserHelper()
{
    return QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("auralis-browser-host.exe"));
}

QStringList nativeHostPaths(const QString &browserId)
{
    const auto chrome = QStringLiteral("Software\\Google\\Chrome\\NativeMessagingHosts\\") + NativeHost;
    if (browserId == QStringLiteral("chrome"))
        return {chrome};
    if (browserId == QStringLiteral("edge"))
        return {QStringLiteral("Software\\Microsoft\\Edge\\NativeMessagingHosts\\") + NativeHost,
                QStringLiteral("Software\\Chromium\\NativeMessagingHosts\\") + NativeHost, chrome};
    return {};
}

bool isLocalFilePath(const QString &path)
{
    return path.size() >= 3 && path[0].isLetter() && path[1] == QLatin1Char(':')
        && (path[2] == QLatin1Char('\\') || path[2] == QLatin1Char('/'));
}

QString manifestPath(HKEY hive, DWORD registryView, const QString &key, bool &unreadable)
{
    std::array<wchar_t, 4096> value;
    DWORD bytes = sizeof(value);
    const auto status = RegGetValueW(hive, reinterpret_cast<LPCWSTR>(key.utf16()), nullptr,
                                    registryView | RRF_RT_REG_SZ, nullptr, value.data(), &bytes);
    unreadable = status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND && status != ERROR_PATH_NOT_FOUND;
    return status == ERROR_SUCCESS ? QString::fromWCharArray(value.data()) : QString();
}

QJsonObject readNativeManifest(const QString &path)
{
    if (!isLocalFilePath(path) || !QFileInfo(path).isFile())
        return {};
    QFile file(path);
    constexpr qint64 manifestLimit = 64 * 1024;
    if (!file.open(QIODevice::ReadOnly) || file.size() > manifestLimit)
        return {};
    return QJsonDocument::fromJson(file.read(manifestLimit)).object();
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

bool blocksNativeHost(QSettings &registry)
{
    return listContains(registry, QStringLiteral("NativeMessagingBlocklist"), NativeHost, true)
        && !listContains(registry, QStringLiteral("NativeMessagingAllowlist"), NativeHost, false);
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
        || blocksNativeHost(registry);
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
    return {isLocalFilePath(executable) && path.isFile() ? executable : QString(),
            queryHttpsAssociation(ASSOCSTR_FRIENDLYAPPNAME)};
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

bool BrowserSetup::isInstalledApplication()
{
    QSettings registration(
        QStringLiteral("HKEY_CURRENT_USER\\Software\\misterhybrid\\Auralis Download Manager"),
        QSettings::NativeFormat);
    const auto installedPath = registration.value(QStringLiteral(".")).toString();
    if (!isLocalFilePath(installedPath))
        return false;
    const auto application = QFileInfo(QCoreApplication::applicationDirPath()).canonicalFilePath();
    return !application.isEmpty()
        && application.compare(QFileInfo(installedPath).canonicalFilePath(), Qt::CaseInsensitive) == 0;
}

BrowserSetup::NativeHostStatus BrowserSetup::nativeHostStatus(const QString &browserId)
{
    const auto locations = nativeHostPaths(browserId);
    if (locations.isEmpty())
        return {};

    bool userHostsAllowed = true;
    const auto path = policyPath(browserId);
    const auto userHostsPolicy = QStringLiteral("NativeMessagingUserLevelHosts");
    for (const auto &root : {QStringLiteral("HKEY_LOCAL_MACHINE"), QStringLiteral("HKEY_CURRENT_USER")}) {
        for (const auto format : {QSettings::Registry64Format, QSettings::Registry32Format}) {
            QSettings policy(root + path, format);
            if (blocksNativeHost(policy))
                return {false, false, false, QCoreApplication::translate("BrowserSetup",
                    "Browser policy blocks the Auralis native messaging host.")};
            if (policy.contains(userHostsPolicy) && !policy.value(userHostsPolicy).toBool())
                userHostsAllowed = false;
        }
    }

    const QFileInfo helperFile(browserHelper());
    const auto helper = helperFile.canonicalFilePath();
    if (helper.isEmpty() || !helperFile.isFile())
        return {false, false, false, QCoreApplication::translate("BrowserSetup",
            "This installation is missing the Auralis browser helper. Reinstall Auralis from its Windows installer.")};
    const auto officialOrigin = QStringLiteral("chrome-extension://") + StoreId + QLatin1Char('/');
    QString manifest;
    for (const auto hive : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
        if (hive == HKEY_CURRENT_USER && !userHostsAllowed)
            continue;
        for (const auto registryView : {RRF_SUBKEY_WOW6432KEY, RRF_SUBKEY_WOW6464KEY}) {
            for (const auto &location : locations) {
                bool unreadable = false;
                manifest = manifestPath(hive, registryView, location, unreadable);
                if (unreadable)
                    return {false, false, false, QCoreApplication::translate("BrowserSetup",
                        "Auralis could not read the browser’s native messaging registration.")};
                if (!manifest.isEmpty())
                    break;
            }
            if (!manifest.isEmpty())
                break;
        }
        if (!manifest.isEmpty())
            break;
    }
    // Browsers use the first manifest registration they find. A stale registration
    // does not make a lower-priority entry usable.
    const auto description = readNativeManifest(manifest);
    const auto program = description.value(QStringLiteral("path")).toString();
    const auto origins = description.value(QStringLiteral("allowed_origins")).toArray();
    const QFileInfo executable(program);
    if (isLocalFilePath(program) && executable.isFile() && !origins.isEmpty()
        && description.value(QStringLiteral("name")).toString() == NativeHost
        && description.value(QStringLiteral("type")).toString() == QStringLiteral("stdio")) {
        if (executable.canonicalFilePath().compare(helper, Qt::CaseInsensitive) != 0)
            return {false, userHostsAllowed, true, QCoreApplication::translate("BrowserSetup",
                "The browser is registered with another download manager installation. Use Repair browser connection to switch it to this Auralis installation.")};
        if (origins.contains(QJsonValue(officialOrigin)))
            return {true, false, false, {}};
    }
    if (!userHostsAllowed)
        return {false, false, false, QCoreApplication::translate("BrowserSetup",
            "Browser policy blocks per-user native messaging hosts. Ask your administrator to register the Auralis browser helper.")};
    return {false, true, false, QCoreApplication::translate("BrowserSetup",
        "The browser connection needs to be registered or repaired.")};
}

QString BrowserSetup::registerNativeHost(const QString &browserId, bool repair)
{
    if (!browserId.isEmpty()) {
        const auto existing = nativeHostStatus(browserId);
        if (existing.registered)
            return {};
        if (!existing.canRegister || (existing.anotherApplication && !repair))
            return existing.problem;
    }
    const auto helper = browserHelper();
    if (!QFileInfo(helper).isFile())
        return QCoreApplication::translate("BrowserSetup", "This installation is missing the Auralis browser helper.");

    QStringList arguments{QStringLiteral("--register-native-only")};
    if (!browserId.isEmpty())
        arguments.push_back(browserId);
    QProcess process;
    process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *arguments) {
        arguments->flags |= CREATE_NO_WINDOW;
    });
    process.start(helper, arguments);
    if (!process.waitForStarted(5000))
        return QCoreApplication::translate("BrowserSetup", "Could not start the Auralis browser helper. %1").arg(process.errorString());
    if (!process.waitForFinished(10000)) {
        process.kill();
        process.waitForFinished(1000);
        return QCoreApplication::translate("BrowserSetup", "The Auralis browser helper did not finish registering the connection.");
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode()) {
        const auto detail = QString::fromUtf8(process.readAllStandardError().left(600)).simplified();
        return detail.isEmpty()
            ? QCoreApplication::translate("BrowserSetup", "The Auralis browser helper could not register the connection (exit code %1).").arg(process.exitCode())
            : QCoreApplication::translate("BrowserSetup", "Could not register the browser connection. %1").arg(detail);
    }
    if (!browserId.isEmpty() && !nativeHostStatus(browserId).registered)
        return QCoreApplication::translate("BrowserSetup",
            "The browser helper ran, but Windows did not report a working Auralis registration for this browser.");
    return {};
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
    QSettings saved(QStringLiteral("HKEY_CURRENT_USER") + path, QSettings::Registry64Format);
    if (QJsonDocument::fromJson(saved.value(SettingsName).toString().toUtf8()).object().value(StoreId).toObject() != auralisPolicy())
        return QCoreApplication::translate("BrowserSetup", "Windows did not retain the Auralis browser policy for this user.");
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
