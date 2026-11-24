#include <windows.h>
#include <sddl.h>

#include <array>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <string_view>

namespace {
constexpr wchar_t SettingsName[] = L"ExtensionSettings";
constexpr wchar_t AuralisPolicy[] =
    LR"({"bobmhloppnfipdjjncalidjenegfgebg":{"installation_mode":"normal_installed","update_url":"https://clients2.google.com/service/update2/crx"}})";
constexpr std::uint64_t ApprovalLifetimeSeconds = 120;

enum ExitCode {
    Applied = 0,
    BadArguments = 2,
    NotElevated = 3,
    WrongAccount = 4,
    Conflict = 5,
    WriteFailed = 6,
    VerificationFailed = 7,
};

struct RegistryKey {
    HKEY value = nullptr;
    ~RegistryKey() { if (value) RegCloseKey(value); }
};

struct TokenHandle {
    HANDLE value = nullptr;
    ~TokenHandle() { if (value) CloseHandle(value); }
};

bool missing(LSTATUS status)
{
    return status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND;
}

bool parseDeadline(std::wstring_view text, std::uint64_t &deadline)
{
    if (text.empty() || text.size() > 12 || text.front() == L'0')
        return false;
    for (wchar_t character : text) {
        if (character < L'0' || character > L'9')
            return false;
        deadline = deadline * 10 + character - L'0';
    }
    return true;
}

bool approvalCurrent(std::uint64_t deadline)
{
    FILETIME fileTime{};
    GetSystemTimeAsFileTime(&fileTime);
    constexpr std::uint64_t SecondsToUnixEpoch = 11644473600ULL;
    const auto ticks = (std::uint64_t(fileTime.dwHighDateTime) << 32) | fileTime.dwLowDateTime;
    const auto seconds = ticks / 10000000ULL;
    if (seconds < SecondsToUnixEpoch)
        return false;
    const auto now = seconds - SecondsToUnixEpoch;
    return deadline > now && deadline - now <= ApprovalLifetimeSeconds;
}

ExitCode verifyToken(const wchar_t *expectedSid)
{
    TokenHandle token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token.value))
        return WrongAccount;

    TOKEN_ELEVATION elevation{};
    DWORD bytes = 0;
    if (!GetTokenInformation(token.value, TokenElevation, &elevation, sizeof(elevation), &bytes)
        || !elevation.TokenIsElevated)
        return NotElevated;

    alignas(TOKEN_USER) std::array<BYTE, sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE> user{};
    if (!GetTokenInformation(token.value, TokenUser, user.data(), DWORD(user.size()), &bytes)
        || bytes < sizeof(TOKEN_USER))
        return WrongAccount;
    const auto sid = reinterpret_cast<const TOKEN_USER *>(user.data())->User.Sid;
    LPWSTR actualSid = nullptr;
    if (!IsValidSid(sid) || !ConvertSidToStringSidW(sid, &actualSid))
        return WrongAccount;
    const bool same = std::wcscmp(actualSid, expectedSid) == 0;
    LocalFree(actualSid);
    return same ? Applied : WrongAccount;
}

enum class CurrentPolicy { Missing, Exact, Other };

CurrentPolicy readPolicy(HKEY key)
{
    wchar_t value[sizeof(AuralisPolicy) / sizeof(wchar_t)]{};
    DWORD bytes = sizeof(value), type = 0;
    const auto status = RegQueryValueExW(key, SettingsName, nullptr, &type,
                                         reinterpret_cast<BYTE *>(value), &bytes);
    if (missing(status))
        return CurrentPolicy::Missing;
    if (status == ERROR_SUCCESS && type == REG_SZ && bytes == sizeof(AuralisPolicy)
        && std::memcmp(value, AuralisPolicy, sizeof(AuralisPolicy)) == 0)
        return CurrentPolicy::Exact;
    return CurrentPolicy::Other;
}

// An elevated process must not follow a registry symbolic link in a user's hive.
// Keep each verified parent open and request write access only for the final key.
LSTATUS openUserChromeKey(std::array<RegistryKey, 4> &keys)
{
    const wchar_t *parts[] = {L"SOFTWARE", L"Policies", L"Google", L"Chrome"};
    HKEY parent = HKEY_CURRENT_USER;
    for (std::size_t index = 0; index < keys.size(); ++index) {
        const bool last = index + 1 == keys.size();
        const REGSAM access = KEY_WOW64_64KEY | KEY_QUERY_VALUE | (last ? KEY_SET_VALUE : 0);
        auto &key = keys[index].value;
        const auto status = RegOpenKeyExW(parent, parts[index], REG_OPTION_OPEN_LINK, access, &key);
        if (status != ERROR_SUCCESS)
            return status;
        if (!missing(RegQueryValueExW(key, L"SymbolicLinkValue", nullptr, nullptr, nullptr, nullptr)))
            return ERROR_INVALID_DATA;
        parent = key;
    }
    return ERROR_SUCCESS;
}

} // namespace

int wmain(int argc, wchar_t **argv)
{
    if (argc != 4)
        return BadArguments;
    const std::wstring_view action(argv[1]), sid(argv[2]);
    std::uint64_t deadline = 0;
    if (action != L"remove" || sid.size() < 5 || sid.size() > 192
        || sid.substr(0, 4) != L"S-1-" || !parseDeadline(argv[3], deadline))
        return BadArguments;
    const auto identity = verifyToken(argv[2]);
    if (identity != Applied)
        return identity;
    if (!approvalCurrent(deadline))
        return Conflict;

    std::array<RegistryKey, 4> userKeys;
    const auto open = openUserChromeKey(userKeys);
    if (missing(open) || open == ERROR_INVALID_DATA)
        return Conflict;
    if (open != ERROR_SUCCESS)
        return WriteFailed;
    const HKEY user = userKeys.back().value;
    if (readPolicy(user) != CurrentPolicy::Exact || !approvalCurrent(deadline))
        return Conflict;
    if (RegDeleteValueW(user, SettingsName) != ERROR_SUCCESS)
        return WriteFailed;
    return readPolicy(user) == CurrentPolicy::Missing ? Applied : VerificationFailed;
}
