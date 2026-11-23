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

struct PolicyValue {
    bool exists = false;
    LSTATUS error = ERROR_SUCCESS;
    QJsonObject settings;
};

constexpr DWORD PolicySizeLimit = 4 * 1024 * 1024;

PolicyValue readPolicyValue(HKEY key, LPCWSTR subkey, DWORD view)
{
    const auto name = reinterpret_cast<LPCWSTR>(SettingsName.utf16());
    const DWORD flags = RRF_RT_REG_SZ | view;
    DWORD bytes = 0;
    const auto status = RegGetValueW(key, subkey, name, flags, nullptr, nullptr, &bytes);
    if (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND)
        return {};
    if (status != ERROR_SUCCESS)
        return {true, status, {}};
    if (!bytes || bytes > PolicySizeLimit || bytes % sizeof(wchar_t))
        return {true, ERROR_INVALID_DATA, {}};

    std::vector<wchar_t> value(bytes / sizeof(wchar_t));
    const auto read = RegGetValueW(key, subkey, name, flags, nullptr, value.data(), &bytes);
    if (read != ERROR_SUCCESS)
        return {true, read, {}};
    if (!bytes || bytes % sizeof(wchar_t) || value[bytes / sizeof(wchar_t) - 1] != L'\0')
        return {true, ERROR_INVALID_DATA, {}};
    const auto text = QString::fromWCharArray(value.data(), qsizetype(bytes / sizeof(wchar_t)) - 1);
    const auto doc = QJsonDocument::fromJson(text.toUtf8());
    return {true, doc.isObject() ? ERROR_SUCCESS : ERROR_INVALID_DATA, doc.object()};
}

PolicyValue readPolicy(HKEY hive, const QString &path, DWORD view)
{
    const QString key = path.mid(1);
    return readPolicyValue(hive, reinterpret_cast<LPCWSTR>(key.utf16()), view);
}

bool canReviewPolicyKey(HKEY hive, const QString &path, REGSAM view)
{
    const QString name = path.mid(1);
    HKEY key = nullptr;
    const auto status = RegOpenKeyExW(hive, reinterpret_cast<LPCWSTR>(name.utf16()), 0, KEY_READ | view, &key);
    if (status == ERROR_SUCCESS)
        RegCloseKey(key);
    return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND;
}

// QSettings opens a registry key for both reading and writing, including permission to
// create subkeys. Request only the rights needed to compare and change this value.
LSTATUS writeUserPolicy(const QString &path, const PolicyValue &expected,
                        const QJsonObject &settings, bool removeValue)
{
    const QString json = removeValue ? QString() : QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact));
    const auto bytes = (json.size() + 1) * sizeof(wchar_t);
    if (bytes > PolicySizeLimit)
        return ERROR_INVALID_DATA;
    const QString keyPath = path.mid(1);
    const auto keyName = reinterpret_cast<LPCWSTR>(keyPath.utf16());
    constexpr REGSAM access = KEY_QUERY_VALUE | KEY_SET_VALUE | KEY_WOW64_64KEY;
    HKEY key = nullptr;
    auto status = RegOpenKeyExW(HKEY_CURRENT_USER, keyName, 0, access, &key);
    if (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND) {
        if (expected.exists || removeValue)
            return ERROR_RETRY;
        status = RegCreateKeyExW(HKEY_CURRENT_USER, keyName, 0, nullptr, REG_OPTION_NON_VOLATILE,
                                 access, nullptr, &key, nullptr);
    }
    if (status != ERROR_SUCCESS)
        return status;

    const auto current = readPolicyValue(key, nullptr, 0);
    if (current.error != ERROR_SUCCESS || current.exists != expected.exists || current.settings != expected.settings) {
        RegCloseKey(key);
        return current.error == ERROR_SUCCESS ? ERROR_RETRY : current.error;
    }
    const auto valueName = reinterpret_cast<LPCWSTR>(SettingsName.utf16());
    if (removeValue) {
        status = RegDeleteValueW(key, valueName);
        if (status == ERROR_FILE_NOT_FOUND)
            status = ERROR_SUCCESS;
    } else {
        status = RegSetValueExW(key, valueName, 0, REG_SZ,
                                reinterpret_cast<const BYTE *>(json.utf16()), DWORD(bytes));
    }
    RegCloseKey(key);
    return status;
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

enum class StoreForceList { Unlisted, Configured, OtherSource };

StoreForceList storeForceList(QSettings &registry, bool chrome)
{
    registry.beginGroup(QStringLiteral("ExtensionInstallForcelist"));
    auto result = StoreForceList::Unlisted;
    for (const auto &key : registry.childKeys()) {
        const auto setting = registry.value(key).toString().trimmed();
        if (setting.section(QLatin1Char(';'), 0, 0).trimmed() != StoreId)
            continue;
        // Chrome's documented default for an ID by itself is the Chrome Web Store.
        if (setting != StoreId + QLatin1Char(';') + StoreUpdate && !(chrome && setting == StoreId)) {
            result = StoreForceList::OtherSource;
            break;
        }
        result = StoreForceList::Configured;
    }
    registry.endGroup();
    return result;
}

bool usesOfficialStore(const QJsonObject &entry)
{
    const auto mode = entry.value(InstallationMode).toString();
    return (mode == NormalInstalled || mode == QStringLiteral("force_installed"))
        && entry.value(UpdateUrl).toString() == StoreUpdate;
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
        || blocksNativeHost(registry);
}

struct Review {
    BrowserSetup::PolicyStatus status;
    PolicyValue policy;
};

Review reviewPolicy(const QString &browserId, const QString &path, QSettings &user)
{
    const QString governed = QCoreApplication::translate("BrowserSetup",
        "Existing browser policies control extension installation. Use the browser’s supported setup or your administrator’s policy.");
    const bool chrome = browserId == QStringLiteral("chrome");
    bool machineConfigured = false;
    for (const auto format : {QSettings::Registry64Format, QSettings::Registry32Format}) {
        const bool wide = format == QSettings::Registry64Format;
        if (!canReviewPolicyKey(HKEY_LOCAL_MACHINE, path, wide ? KEY_WOW64_64KEY : KEY_WOW64_32KEY))
            return {{false, false, governed}, {}};
        QSettings machine(QStringLiteral("HKEY_LOCAL_MACHINE") + path, format);
        const auto forceList = storeForceList(machine, chrome);
        const auto view = wide ? RRF_SUBKEY_WOW6464KEY : RRF_SUBKEY_WOW6432KEY;
        const auto configured = readPolicy(HKEY_LOCAL_MACHINE, path, view);
        if (existingPolicyBlocksSetup(machine) || forceList == StoreForceList::OtherSource
            || configured.error != ERROR_SUCCESS || machine.status() != QSettings::NoError)
            return {{false, false, governed}, {}};
        if (configured.exists) {
            if (!usesOfficialStore(configured.settings.value(StoreId).toObject()))
                return {{false, false, governed}, {}};
            machineConfigured = true;
        }
        machineConfigured |= forceList == StoreForceList::Configured;
    }
    if (!canReviewPolicyKey(HKEY_CURRENT_USER, path, KEY_WOW64_64KEY))
        return {{false, false, governed}, {}};
    const auto userForceList = storeForceList(user, chrome);
    if (existingPolicyBlocksSetup(user) || userForceList == StoreForceList::OtherSource
        || user.status() != QSettings::NoError)
        return {{false, false, governed}, {}};
    if (machineConfigured)
        return {{false, true, {}}, {}};

    const auto configured = readPolicy(HKEY_CURRENT_USER, path, RRF_SUBKEY_WOW6464KEY);
    if (configured.error != ERROR_SUCCESS)
        return {{false, false, governed}, {}};
    const auto &settings = configured.settings;

    const auto existing = settings.value(StoreId);
    const auto entry = existing.toObject();
    if (usesOfficialStore(entry)) {
        QSettings ownership;
        const bool removable = userForceList == StoreForceList::Unlisted && entry == auralisPolicy()
            && ownership.contains(ownershipKey(browserId));
        return {{false, true, {}, removable}, configured};
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
    if (userForceList == StoreForceList::Configured)
        return {{false, true, {}}, configured};
    return {{true, false, {}}, configured};
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
    auto settings = review.policy.settings;
    settings.insert(StoreId, auralisPolicy());
    const auto error = writeUserPolicy(path, review.policy, settings, false);
    if (error == ERROR_RETRY)
        return QCoreApplication::translate("BrowserSetup", "The browser policy changed while saving. Check browser setup and try again.");
    if (error == ERROR_ACCESS_DENIED)
        return QCoreApplication::translate("BrowserSetup",
            "Windows denied permission to save automatic setup for this account. Use Install manually, or ask your administrator to configure the extension.");
    if (error != ERROR_SUCCESS)
        return QCoreApplication::translate("BrowserSetup",
            "Could not save browser setup for this Windows account (Windows error %1).").arg(error);
    const auto saved = readPolicy(HKEY_CURRENT_USER, path, RRF_SUBKEY_WOW6464KEY);
    if (saved.error != ERROR_SUCCESS || saved.settings.value(StoreId).toObject() != auralisPolicy())
        return QCoreApplication::translate("BrowserSetup", "Windows did not retain the Auralis browser policy for this user.");
    QSettings ownership;
    ownership.setValue(ownershipKey(browserId), review.policy.exists);
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
    auto settings = review.policy.settings;
    settings.remove(StoreId);
    const bool removeValue = settings.isEmpty() && !ownership.value(key).toBool();
    const auto error = writeUserPolicy(path, review.policy, settings, removeValue);
    if (error != ERROR_SUCCESS)
        return QCoreApplication::translate("BrowserSetup",
            "Could not remove automatic browser setup for this Windows account (Windows error %1).").arg(error);
    ownership.remove(key);
    return {};
}
#endif
