#include "BrowserSetup.h"

#ifdef Q_OS_WIN
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
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
#include <objbase.h>
#include <sddl.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <winver.h>
#include <array>
#include <optional>
#include <utility>
#include <vector>

#ifdef AURALIS_CHROME_APPROVAL_ENABLED
#include "AuralisChromeApprovalDigest.h"
#endif

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
    QString raw;
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
        return {true, status, {}, {}};
    if (!bytes || bytes > PolicySizeLimit || bytes % sizeof(wchar_t))
        return {true, ERROR_INVALID_DATA, {}, {}};

    std::vector<wchar_t> value(bytes / sizeof(wchar_t));
    const auto read = RegGetValueW(key, subkey, name, flags, nullptr, value.data(), &bytes);
    if (read != ERROR_SUCCESS)
        return {true, read, {}, {}};
    if (!bytes || bytes % sizeof(wchar_t) || value[bytes / sizeof(wchar_t) - 1] != L'\0')
        return {true, ERROR_INVALID_DATA, {}, {}};
    const auto text = QString::fromWCharArray(value.data(), qsizetype(bytes / sizeof(wchar_t)) - 1);
    const auto doc = QJsonDocument::fromJson(text.toUtf8());
    return {true, doc.isObject() ? ERROR_SUCCESS : ERROR_INVALID_DATA, doc.object(), text};
}

PolicyValue readPolicy(HKEY hive, const QString &path, DWORD view)
{
    const QString key = path.mid(1);
    return readPolicyValue(hive, reinterpret_cast<LPCWSTR>(key.utf16()), view);
}

std::optional<bool> existingReadablePolicyKey(HKEY hive, const QString &path, REGSAM view)
{
    const QString name = path.mid(1);
    HKEY key = nullptr;
    const auto status = RegOpenKeyExW(hive, reinterpret_cast<LPCWSTR>(name.utf16()), 0, KEY_READ | view, &key);
    if (status == ERROR_SUCCESS) {
        RegCloseKey(key);
        return true;
    }
    if (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND)
        return false;
    return std::nullopt;
}

// QSettings opens a registry key for both reading and writing, including permission to
// create subkeys. Request only the rights needed to compare and change this value.
LSTATUS writeUserPolicy(const QString &path, const PolicyValue &expected,
                        const QString &json, bool removeValue)
{
    const auto bytes = (json.size() + 1) * sizeof(wchar_t);
    if (bytes > PolicySizeLimit)
        return ERROR_INVALID_DATA;
    const QString keyPath = path.mid(1);
    const auto keyName = reinterpret_cast<LPCWSTR>(keyPath.utf16());
    constexpr REGSAM access = KEY_QUERY_VALUE | KEY_SET_VALUE | KEY_WOW64_64KEY;
    HKEY key = nullptr;
    auto status = RegOpenKeyExW(HKEY_CURRENT_USER, keyName, 0, access, &key);
    if (status != ERROR_SUCCESS)
        return status;

    const auto current = readPolicyValue(key, nullptr, 0);
    if (current.error != ERROR_SUCCESS || current.exists != expected.exists || current.raw != expected.raw) {
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

bool supportsChromePolicyRefresh(const QString &executable)
{
    if (!isLocalFilePath(executable)
        || QFileInfo(executable).fileName().compare(QStringLiteral("chrome.exe"), Qt::CaseInsensitive) != 0)
        return false;

    const auto path = reinterpret_cast<LPCWSTR>(executable.utf16());
    DWORD legacyHandle = 0;
    const DWORD size = GetFileVersionInfoSizeW(path, &legacyHandle);
    if (!size || size > 1024 * 1024)
        return false;
    std::vector<BYTE> version(size);
    if (!GetFileVersionInfoW(path, 0, size, version.data()))
        return false;

    LPVOID raw = nullptr;
    UINT bytes = 0;
    if (!VerQueryValueW(version.data(), L"\\", &raw, &bytes) || !raw || bytes < sizeof(VS_FIXEDFILEINFO))
        return false;
    const auto fixed = static_cast<const VS_FIXEDFILEINFO *>(raw);
    // Chrome M142 introduced the running instance's platform policy refresh switch.
    return fixed->dwSignature == VS_FFI_SIGNATURE && HIWORD(fixed->dwFileVersionMS) >= 142;
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

struct OwnedUserPolicy {
    PolicyValue policy;
    bool previouslyExisted;
};

std::optional<OwnedUserPolicy> ownedUserPolicy(QSettings &ownership, const QString &browserId, const QString &path)
{
    // QSettings on Windows stores booleans as strings. Require an explicit recorded value.
    const auto prior = ownership.value(ownershipKey(browserId)).toString();
    if (prior != QStringLiteral("true") && prior != QStringLiteral("false"))
        return std::nullopt;
    auto policy = readPolicy(HKEY_CURRENT_USER, path, RRF_SUBKEY_WOW6464KEY);
    if (policy.error != ERROR_SUCCESS || !policy.exists || policy.settings.value(StoreId).toObject() != auralisPolicy())
        return std::nullopt;
    return OwnedUserPolicy{std::move(policy), prior == QStringLiteral("true")};
}

const QString ChromeOfferPath = QStringLiteral("Software\\Google\\Chrome\\Extensions\\") + StoreId;
constexpr wchar_t OfferUpdate[] = L"update_url";
constexpr wchar_t OfferOwner[] = L"AuralisOfferOwner";
const QString OfferOwnerValue = QStringLiteral("Auralis Download Manager");

struct RegistryKey {
    HKEY value = nullptr;
    ~RegistryKey() { if (value) RegCloseKey(value); }
};

bool missingRegistryKey(LSTATUS status)
{
    return status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND;
}

enum class OfferValue { Missing, Exact, Other };
enum class OfferState { Missing, Empty, Preparing, Registered, Owned, Conflict };

OfferValue readOfferValue(HKEY key, LPCWSTR name, const QString &expected)
{
    std::array<wchar_t, 256> value{};
    DWORD bytes = sizeof(value), type = 0;
    const auto status = RegQueryValueExW(key, name, nullptr, &type,
        reinterpret_cast<BYTE *>(value.data()), &bytes);
    if (missingRegistryKey(status))
        return OfferValue::Missing;
    if (status == ERROR_SUCCESS && type == REG_SZ && bytes == (expected.size() + 1) * sizeof(wchar_t)
        && value[expected.size()] == L'\0'
        && QString::fromWCharArray(value.data(), expected.size()) == expected)
        return OfferValue::Exact;
    return OfferValue::Other;
}

OfferState inspectOfferKey(HKEY key)
{
    DWORD subkeys = 0, values = 0;
    if (RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, &subkeys, nullptr, nullptr,
                         &values, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS
        || !missingRegistryKey(RegQueryValueExW(key, L"SymbolicLinkValue", nullptr, nullptr, nullptr, nullptr)))
        return OfferState::Conflict;

    const auto update = readOfferValue(key, OfferUpdate, StoreUpdate);
    const bool owner = readOfferValue(key, OfferOwner, OfferOwnerValue) == OfferValue::Exact;
    if (update == OfferValue::Exact)
        return owner && subkeys == 0 && values == 2 ? OfferState::Owned : OfferState::Registered;
    if (update == OfferValue::Missing && subkeys == 0) {
        if (values == 0)
            return OfferState::Empty;
        if (owner && values == 1)
            return OfferState::Preparing;
    }
    return OfferState::Conflict;
}

OfferState inspectOffer(HKEY hive, REGSAM view = 0)
{
    RegistryKey key;
    const auto status = RegOpenKeyExW(hive, reinterpret_cast<LPCWSTR>(ChromeOfferPath.utf16()),
        REG_OPTION_OPEN_LINK, KEY_QUERY_VALUE | view, &key.value);
    if (status == ERROR_SUCCESS)
        return inspectOfferKey(key.value);
    return missingRegistryKey(status) ? OfferState::Missing : OfferState::Conflict;
}

LSTATUS setOfferValue(HKEY key, LPCWSTR name, const QString &value)
{
    return RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE *>(value.utf16()),
                           DWORD((value.size() + 1) * sizeof(wchar_t)));
}

QString existingOfferProblem()
{
    return QCoreApplication::translate("BrowserSetup",
        "Chrome’s existing extension registration prevents Auralis from adding an offer. Open the Chrome Web Store to install the extension.");
}

#ifdef AURALIS_CHROME_APPROVAL_ENABLED
struct ProcessHandle {
    HANDLE value = nullptr;
    ProcessHandle() = default;
    explicit ProcessHandle(HANDLE handle) : value(handle) {}
    ProcessHandle(const ProcessHandle &) = delete;
    ProcessHandle &operator=(const ProcessHandle &) = delete;
    ProcessHandle(ProcessHandle &&other) noexcept : value(std::exchange(other.value, nullptr)) {}
    ~ProcessHandle() { if (valid()) CloseHandle(value); }
    bool valid() const { return value && value != INVALID_HANDLE_VALUE; }
};

QString chromeApprovalAccountSid()
{
    ProcessHandle token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token.value))
        return {};
    TOKEN_ELEVATION_TYPE type{};
    DWORD bytes = 0;
    if (!GetTokenInformation(token.value, TokenElevationType, &type, sizeof(type), &bytes)
        || type != TokenElevationTypeLimited)
        return {};
    bytes = 0;
    if (GetTokenInformation(token.value, TokenUser, nullptr, 0, &bytes)
        || GetLastError() != ERROR_INSUFFICIENT_BUFFER || bytes < sizeof(TOKEN_USER)
        || bytes > sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE)
        return {};
    std::vector<unsigned char> user(bytes);
    if (!GetTokenInformation(token.value, TokenUser, user.data(), bytes, &bytes))
        return {};
    LPWSTR raw = nullptr;
    if (!ConvertSidToStringSidW(reinterpret_cast<const TOKEN_USER *>(user.data())->User.Sid, &raw))
        return {};
    const auto sid = QString::fromWCharArray(raw);
    LocalFree(raw);
    return sid;
}

bool chromeApprovalAvailable()
{
    const auto chromePath = policyPath(QStringLiteral("chrome"));
    // The elevated helper opens an existing policy key without following registry links.
    return existingReadablePolicyKey(HKEY_CURRENT_USER, chromePath, KEY_WOW64_64KEY).value_or(false)
        && BrowserSetup::isInstalledApplication() && !chromeApprovalAccountSid().isEmpty();
}

QString chromeApprovalOwnershipKey()
{
    return QStringLiteral("BrowserIntegration/approvedChromeExtension");
}

QString approvedChromePolicyValue()
{
    return QString::fromUtf8(QJsonDocument(QJsonObject{{StoreId, auralisPolicy()}}).toJson(QJsonDocument::Compact));
}

bool canApproveOwnedRemoval(const OwnedUserPolicy &owned)
{
    // The helper can delete the entire exact value only if Auralis created it.
    return !owned.previouslyExisted && owned.policy.raw == approvedChromePolicyValue();
}

// Keep the verified file and each directory open without delete sharing while
// Windows resolves the path for elevation. Check the actual opened name too.
bool isSameLocalPath(HANDLE handle, const QString &expected)
{
    std::vector<wchar_t> buffer(32768);
    const DWORD count = GetFinalPathNameByHandleW(handle, buffer.data(), DWORD(buffer.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (!count || count >= buffer.size())
        return false;
    const auto path = QString::fromWCharArray(buffer.data(), qsizetype(count));
    if (!path.startsWith(QStringLiteral("\\\\?\\")))
        return false;
    return QDir::cleanPath(QDir::fromNativeSeparators(path.mid(4))).compare(QDir::cleanPath(expected), Qt::CaseInsensitive) == 0;
}

bool holdApprovalDirectory(const QString &directory, std::vector<ProcessHandle> &held)
{
    if (!isLocalFilePath(directory))
        return false;
    const auto native = QDir::toNativeSeparators(directory);
    QString path = native.left(3);
    if (GetDriveTypeW(reinterpret_cast<LPCWSTR>(path.utf16())) != DRIVE_FIXED)
        return false;
    auto lock = [&](const QString &part) {
        const auto full = QDir::toNativeSeparators(part);
        ProcessHandle handle(CreateFileW(reinterpret_cast<LPCWSTR>(full.utf16()), FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
        BY_HANDLE_FILE_INFORMATION info{};
        if (!handle.valid() || !GetFileInformationByHandle(handle.value, &info)
            || !(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
            || !isSameLocalPath(handle.value, QDir::fromNativeSeparators(full)))
            return false;
        held.push_back(std::move(handle));
        return true;
    };
    if (!lock(path))
        return false;
    const auto parts = native.mid(3).split(QLatin1Char('\\'), Qt::SkipEmptyParts);
    for (const auto &part : parts) {
        if (part == QStringLiteral(".") || part == QStringLiteral(".."))
            return false;
        if (!path.endsWith(QLatin1Char('\\')))
            path += QLatin1Char('\\');
        path += part;
        if (!lock(path))
            return false;
    }
    return true;
}

bool verifyApprovalExecutable(const ProcessHandle &file, const QString &path)
{
    BY_HANDLE_FILE_INFORMATION info{};
    const auto expected = QByteArray::fromHex(AURALIS_CHROME_APPROVAL_SHA256);
    if (!file.valid() || expected.size() != 32 || !GetFileInformationByHandle(file.value, &info)
        || (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))
        || info.nFileSizeHigh != 0 || !info.nFileSizeLow || info.nFileSizeLow > 4 * 1024 * 1024
        || !isSameLocalPath(file.value, QDir::fromNativeSeparators(path)))
        return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    std::array<char, 64 * 1024> buffer;
    DWORD total = 0;
    while (total < info.nFileSizeLow) {
        DWORD bytes = 0;
        if (!ReadFile(file.value, buffer.data(), DWORD(buffer.size()), &bytes, nullptr) || !bytes)
            return false;
        hash.addData(QByteArrayView(buffer.data(), qsizetype(bytes)));
        total += bytes;
    }
    return total == info.nFileSizeLow && hash.result() == expected;
}
#endif

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

QStringList BrowserSetup::browserPolicyRefreshArguments(const QString &browserId, const QString &executable)
{
    if (browserId == QStringLiteral("chrome") && supportsChromePolicyRefresh(executable))
        return {QStringLiteral("--refresh-platform-policy")};
    return {};
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
    const auto unreadablePolicy = QCoreApplication::translate("BrowserSetup",
        "Auralis could not read the browser’s native messaging policy.");
    for (const auto hive : {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER}) {
        const auto root = hive == HKEY_LOCAL_MACHINE ? QStringLiteral("HKEY_LOCAL_MACHINE") : QStringLiteral("HKEY_CURRENT_USER");
        for (const auto format : {QSettings::Registry64Format, QSettings::Registry32Format}) {
            const auto view = format == QSettings::Registry64Format ? KEY_WOW64_64KEY : KEY_WOW64_32KEY;
            const auto existing = existingReadablePolicyKey(hive, path, view);
            if (!existing)
                return {false, false, false, unreadablePolicy};
            // A settings lookup can create its base key. Status checks skip absent keys.
            if (!*existing)
                continue;
            QSettings policy(root + path, format);
            if (blocksNativeHost(policy))
                return {false, false, false, QCoreApplication::translate("BrowserSetup",
                    "Browser policy blocks the Auralis native messaging host.")};
            if (policy.contains(userHostsPolicy) && !policy.value(userHostsPolicy).toBool())
                userHostsAllowed = false;
            if (policy.status() != QSettings::NoError)
                return {false, false, false, unreadablePolicy};
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

BrowserSetup::OfferStatus BrowserSetup::chromeOfferStatus()
{
    const auto user = inspectOffer(HKEY_CURRENT_USER);
    const auto machine = inspectOffer(HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY);
    // Chrome selects the machine key first when both keys exist for the same ID.
    const auto effective = machine == OfferState::Missing ? user : machine;
    const bool registered = effective == OfferState::Registered || effective == OfferState::Owned;
    const bool available = registered || (machine == OfferState::Missing
        && (user == OfferState::Missing || user == OfferState::Empty || user == OfferState::Preparing));
    return {available, registered, user == OfferState::Owned || user == OfferState::Preparing,
            available ? QString() : existingOfferProblem()};
}

QString BrowserSetup::registerChromeOffer()
{
    const auto offer = chromeOfferStatus();
    if (offer.registered || !offer.available)
        return offer.problem;

    RegistryKey key;
    const auto path = reinterpret_cast<LPCWSTR>(ChromeOfferPath.utf16());
    constexpr REGSAM access = KEY_QUERY_VALUE | KEY_SET_VALUE;
    auto result = RegOpenKeyExW(HKEY_CURRENT_USER, path, REG_OPTION_OPEN_LINK, access, &key.value);
    if (missingRegistryKey(result))
        result = RegCreateKeyExW(HKEY_CURRENT_USER, path, 0, nullptr, REG_OPTION_NON_VOLATILE,
                                 access, nullptr, &key.value, nullptr);
    if (result == ERROR_SUCCESS) {
        const auto state = inspectOfferKey(key.value);
        if (state == OfferState::Owned || state == OfferState::Registered)
            return {};
        if (state != OfferState::Empty && state != OfferState::Preparing)
            return existingOfferProblem();

        // Mark ownership before enabling the offer so a failed write can be retried or removed.
        if (state == OfferState::Empty)
            result = setOfferValue(key.value, OfferOwner, OfferOwnerValue);
        if (result == ERROR_SUCCESS)
            result = setOfferValue(key.value, OfferUpdate, StoreUpdate);
    }
    if (result != ERROR_SUCCESS)
        return QCoreApplication::translate("BrowserSetup", "Windows could not save the Chrome extension offer (Windows error %1).").arg(result);
    if (inspectOfferKey(key.value) != OfferState::Owned)
        return QCoreApplication::translate("BrowserSetup", "Windows did not retain the Chrome extension offer.");
    return {};
}

QString BrowserSetup::removeChromeOffer()
{
    RegistryKey key;
    auto result = RegOpenKeyExW(HKEY_CURRENT_USER, reinterpret_cast<LPCWSTR>(ChromeOfferPath.utf16()),
        REG_OPTION_OPEN_LINK, KEY_QUERY_VALUE | KEY_SET_VALUE, &key.value);
    if (result == ERROR_SUCCESS) {
        const auto state = inspectOfferKey(key.value);
        if (state != OfferState::Owned && state != OfferState::Preparing)
            return QCoreApplication::translate("BrowserSetup", "Chrome’s extension offer changed. Only an offer created by Auralis can be removed.");
        if (state == OfferState::Owned)
            result = RegDeleteValueW(key.value, OfferUpdate);
        // Delete only the two recognized values, never the key or anything else in it.
        if (result == ERROR_SUCCESS && inspectOfferKey(key.value) == OfferState::Preparing)
            result = RegDeleteValueW(key.value, OfferOwner);
    }
    if (result != ERROR_SUCCESS)
        return QCoreApplication::translate("BrowserSetup", "Windows could not remove the Chrome extension offer (Windows error %1).").arg(result);
    if (readOfferValue(key.value, OfferOwner, OfferOwnerValue) == OfferValue::Exact)
        return QCoreApplication::translate("BrowserSetup", "Windows did not remove the Chrome extension offer.");
    return {};
}

bool BrowserSetup::legacyPolicyRemovable(const QString &browserId)
{
    const auto path = policyPath(browserId);
    if (path.isEmpty())
        return false;
    QSettings ownership;
    ownership.setFallbacksEnabled(false);
    return ownedUserPolicy(ownership, browserId, path).has_value();
}

QString BrowserSetup::removeLegacyPolicy(const QString &browserId, bool *windowsApprovalRequired)
{
    if (windowsApprovalRequired)
        *windowsApprovalRequired = false;
    const auto path = policyPath(browserId);
    if (path.isEmpty())
        return QCoreApplication::translate("BrowserSetup", "Managed setup is unavailable for this browser.");
    QSettings ownership;
    ownership.setFallbacksEnabled(false);
    const auto owned = ownedUserPolicy(ownership, browserId, path);
    if (!owned)
        return QCoreApplication::translate("BrowserSetup", "The existing browser policy was changed or was configured outside Auralis.");
    const auto key = ownershipKey(browserId);
    auto settings = owned->policy.settings;
    settings.remove(StoreId);
    const bool removeValue = settings.isEmpty() && !owned->previouslyExisted;
    const auto json = removeValue ? QString() : QString::fromUtf8(QJsonDocument(settings).toJson(QJsonDocument::Compact));
    const auto error = writeUserPolicy(path, owned->policy, json, removeValue);
#ifdef AURALIS_CHROME_APPROVAL_ENABLED
    if (windowsApprovalRequired && error == ERROR_ACCESS_DENIED && browserId == QStringLiteral("chrome")
        && canApproveOwnedRemoval(*owned))
        *windowsApprovalRequired = chromeApprovalAvailable();
#endif
    if (error != ERROR_SUCCESS)
        return QCoreApplication::translate("BrowserSetup",
            "Could not remove automatic browser setup for this Windows account (Windows error %1).").arg(error);
    const auto saved = readPolicy(HKEY_CURRENT_USER, path, RRF_SUBKEY_WOW6464KEY);
    if (saved.error != ERROR_SUCCESS || saved.settings.contains(StoreId))
        return QCoreApplication::translate("BrowserSetup", "Windows did not retain the Auralis browser policy change.");
    ownership.remove(key);
#ifdef AURALIS_CHROME_APPROVAL_ENABLED
    if (browserId == QStringLiteral("chrome"))
        ownership.remove(chromeApprovalOwnershipKey());
#endif
    return {};
}

QString BrowserSetup::removeLegacyChromePolicyWithAdministratorApproval()
{
    const auto unavailable = QCoreApplication::translate("BrowserSetup",
        "Windows approval requires an installed Auralis application and an administrator account with its own approval token.");
#ifdef AURALIS_CHROME_APPROVAL_ENABLED
    const auto sid = chromeApprovalAccountSid();
    if (sid.isEmpty() || !isInstalledApplication())
        return unavailable;

    const auto browser = QStringLiteral("chrome");
    const auto path = policyPath(browser);
    if (!existingReadablePolicyKey(HKEY_CURRENT_USER, path, KEY_WOW64_64KEY).value_or(false))
        return QCoreApplication::translate("BrowserSetup", "The Chrome policy changed before approval. Check browser setup again.");
    QSettings ownership;
    ownership.setFallbacksEnabled(false);
    const auto owned = ownedUserPolicy(ownership, browser, path);
    if (!owned || !canApproveOwnedRemoval(*owned))
        return QCoreApplication::translate("BrowserSetup", "The Chrome policy changed before approval. Check browser setup again.");
    if (!ownership.isWritable())
        return QCoreApplication::translate("BrowserSetup", "Auralis could not save the undo information for Windows approval.");

    const auto directory = QFileInfo(QCoreApplication::applicationDirPath()).canonicalFilePath();
    const auto workingDirectory = QDir::toNativeSeparators(directory);
    std::vector<ProcessHandle> directories;
    const auto invalidHelper = QCoreApplication::translate("BrowserSetup",
        "Auralis could not verify its Windows approval helper. Reinstall Auralis from its official Windows installer.");
    if (!holdApprovalDirectory(directory, directories))
        return invalidHelper;
    const auto program = QDir::toNativeSeparators(QDir(directory).filePath(QStringLiteral("auralis-chrome-approval.exe")));
    ProcessHandle helper(CreateFileW(reinterpret_cast<LPCWSTR>(program.utf16()), GENERIC_READ, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
    if (!verifyApprovalExecutable(helper, program))
        return invalidHelper;

    const auto expires = QDateTime::currentSecsSinceEpoch() + 90;
    const auto parameters = QStringLiteral("remove %1 %2").arg(sid).arg(expires);
    SHELLEXECUTEINFOW execute{};
    execute.cbSize = sizeof(execute);
    execute.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
    execute.lpVerb = L"runas";
    execute.lpFile = reinterpret_cast<LPCWSTR>(program.utf16());
    execute.lpParameters = reinterpret_cast<LPCWSTR>(parameters.utf16());
    execute.lpDirectory = reinterpret_cast<LPCWSTR>(workingDirectory.utf16());
    execute.nShow = SW_HIDE;
    const auto com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    const bool launched = ShellExecuteExW(&execute) != FALSE;
    const auto launchError = launched ? ERROR_SUCCESS : GetLastError();
    if (SUCCEEDED(com))
        CoUninitialize();
    ProcessHandle child(execute.hProcess);
    if (!launched || !child.valid()) {
        if (launchError == ERROR_CANCELLED)
            return QCoreApplication::translate("BrowserSetup", "Windows administrator approval was cancelled.");
        return QCoreApplication::translate("BrowserSetup", "Could not start Windows administrator approval (Windows error %1).")
            .arg(launchError == ERROR_SUCCESS ? ERROR_INVALID_HANDLE : launchError);
    }

    // The helper independently checks expiry before writing. Waiting through the expiry
    // prevents a late approval from silently applying a new policy after this times out.
    const auto remaining = qBound(qint64(0), (expires + 2 - QDateTime::currentSecsSinceEpoch()) * 1000, qint64(92000));
    const auto wait = WaitForSingleObject(child.value, DWORD(remaining));
    if (wait == WAIT_TIMEOUT)
        return QCoreApplication::translate("BrowserSetup", "Windows approval timed out. Check Chrome setup before trying again.");
    DWORD exitCode = 0;
    if (wait != WAIT_OBJECT_0 || !GetExitCodeProcess(child.value, &exitCode))
        return QCoreApplication::translate("BrowserSetup", "Could not read the result of Windows administrator approval.");
    switch (exitCode) {
    case 0: {
        const auto saved = readPolicy(HKEY_CURRENT_USER, path, RRF_SUBKEY_WOW6464KEY);
        if (saved.error != ERROR_SUCCESS || saved.exists)
            break;
        const auto key = ownershipKey(browser);
        const auto approvedKey = chromeApprovalOwnershipKey();
        ownership.remove(key);
        ownership.remove(approvedKey);
        ownership.sync();
        if (ownership.status() != QSettings::NoError)
            return QCoreApplication::translate("BrowserSetup", "Chrome setup changed, but Auralis could not save its undo information.");
        return {};
    }
    case 3:
        return QCoreApplication::translate("BrowserSetup", "Windows did not grant administrator approval.");
    case 4:
        return QCoreApplication::translate("BrowserSetup", "Approve with the same Windows account that is running Auralis. Setup did not change another account.");
    case 5:
        if (QDateTime::currentSecsSinceEpoch() >= expires)
            return QCoreApplication::translate("BrowserSetup", "Windows approval timed out. Check Chrome setup before trying again.");
        return QCoreApplication::translate("BrowserSetup", "The Chrome policy changed before approval. Check browser setup again.");
    case 6:
        return QCoreApplication::translate("BrowserSetup", "Windows could not change the Chrome policy with this approval. Use the browser’s supported setup or contact your administrator.");
    case 7:
        break;
    default:
        return QCoreApplication::translate("BrowserSetup", "Windows administrator approval ended unexpectedly (exit code %1).").arg(exitCode);
    }
    return QCoreApplication::translate("BrowserSetup", "Windows did not retain the Auralis browser policy change.");
#else
    return unavailable;
#endif
}
#endif
