using System.Text.Json;

namespace Auralis.WinUI;

/// Parses the narrow set of commands that the future packaged web interface
/// can ask the native host to perform. The host must also enforce that no
/// untrusted navigation is allowed and must never expose the downloader token.
internal sealed record BridgeMessage(long Id, string Command, ulong DownloadId, string? Url, bool Later)
{
    internal const string TrustedOrigin = "https://auralis.local";
    internal static BridgeMessage Parse(string source, string json)
    {
        if (!Uri.TryCreate(source, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            uri.Host != "auralis.local" || !uri.IsDefaultPort || uri.UserInfo.Length != 0)
            throw new InvalidOperationException("Untrusted interface origin.");
        if (json.Length > 16_384) throw new InvalidOperationException("Interface message is too large.");
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 8 });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("id", out var idValue) ||
            !idValue.TryGetInt64(out long id) || id <= 0 || id > 9_007_199_254_740_991L ||
            !root.TryGetProperty("command", out var commandValue) || commandValue.ValueKind != JsonValueKind.String)
            throw new InvalidOperationException("Invalid interface request.");
        string command = commandValue.GetString()!;
        if (command is "dashboard_snapshot" or "dashboard_visuals") return new(id, command, 0, null, false);
        if (command is "start_download" or "pause_download")
        {
            if (!root.TryGetProperty("downloadId", out var downloadId) || !downloadId.TryGetUInt64(out ulong value) || value == 0)
                throw new InvalidOperationException("Invalid download ID.");
            return new(id, command, value, null, false);
        }
        if (command == "add_download")
        {
            if (!root.TryGetProperty("url", out var urlValue) || urlValue.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Invalid download link.");
            string url = urlValue.GetString()?.Trim() ?? "";
            if (url.Length == 0 || System.Text.Encoding.UTF8.GetByteCount(url) > 8192 ||
                !(url.StartsWith("http://", StringComparison.Ordinal) || url.StartsWith("https://", StringComparison.Ordinal) || url.StartsWith("ftp://", StringComparison.Ordinal) || url.StartsWith("magnet:", StringComparison.Ordinal)))
                throw new InvalidOperationException("Unsupported download link.");
            bool later = false;
            if (root.TryGetProperty("later", out var laterValue))
            {
                if (laterValue.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new InvalidOperationException("Invalid queue choice.");
                later = laterValue.GetBoolean();
            }
            return new(id, command, 0, url, later);
        }
        throw new InvalidOperationException("Unsupported interface command.");
    }
}
