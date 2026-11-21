using System.Text.Json;

namespace Auralis.WinUI;

/// Parses the narrow set of commands that the future packaged web interface
/// can ask the native host to perform. The host must also enforce that no
/// untrusted navigation is allowed and must never expose the downloader token.
internal sealed record BridgeMessage(long Id, string Command, ulong DownloadId, string? Url, bool Later, string? Key = null, string? Value = null, NativeAppearance? Appearance = null, string? Label = null, int Width = 0, int Height = 0)
{
    internal const string TrustedOrigin = "https://auralis.local";
    internal static BridgeMessage Parse(string source, string json)
    {
        if (!Uri.TryCreate(source, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            uri.Host != "auralis.local" || !uri.IsDefaultPort || uri.UserInfo.Length != 0)
            throw new InvalidOperationException("Untrusted interface origin.");
        if (json.Length > 65_536) throw new InvalidOperationException("Interface message is too large.");
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 8 });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("id", out var idValue) ||
            !idValue.TryGetInt64(out long id) || id <= 0 || id > 9_007_199_254_740_991L ||
            !root.TryGetProperty("command", out var commandValue) || commandValue.ValueKind != JsonValueKind.String)
            throw new InvalidOperationException("Invalid interface request.");
        string command = commandValue.GetString()!;
        if (command is "export_theme_file" or "export_material_file")
        {
            if (!root.TryGetProperty("contents", out var contentsValue) || contentsValue.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Invalid export.");
            string contents=contentsValue.GetString()!;
            int limit=command=="export_theme_file" ? 32_768 : 16_384;
            if (System.Text.Encoding.UTF8.GetByteCount(contents)>limit) throw new InvalidOperationException("Export is too large.");
            using var exported=JsonDocument.Parse(contents,new JsonDocumentOptions { MaxDepth=32 });
            if (exported.RootElement.ValueKind!=JsonValueKind.Object) throw new InvalidOperationException("Invalid export.");
            return new(id,command,0,null,false,Value:contents);
        }
        if (command == "open_glass_window")
        {
            if (!root.TryGetProperty("label", out var labelValue) || labelValue.ValueKind != JsonValueKind.String ||
                !root.TryGetProperty("url", out var urlValue) || urlValue.ValueKind != JsonValueKind.String ||
                !root.TryGetProperty("width", out var widthValue) || !widthValue.TryGetInt32(out int width) ||
                !root.TryGetProperty("height", out var heightValue) || !heightValue.TryGetInt32(out int height))
                throw new InvalidOperationException("Invalid window request.");
            string label = labelValue.GetString()!;
            string url = urlValue.GetString()!;
            if (label.Length is < 1 or > 80 || !label.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_') ||
                url.Length > 2048 || !url.StartsWith("/?", StringComparison.Ordinal) || url.Contains('\\') ||
                !Uri.TryCreate(TrustedOrigin + url, UriKind.Absolute, out var target) || target.Host != "auralis.local" ||
                width is < 320 or > 2400 || height is < 120 or > 1600)
                throw new InvalidOperationException("Unsupported window request.");
            return new(id, command, 0, url, false, Label: label, Width: width, Height: height);
        }
        if (command == "set_native_appearance")
        {
            if (!root.TryGetProperty("appearance", out var appearance)) throw new InvalidOperationException("Missing appearance.");
            return new(id, command, 0, null, false, Appearance: NativeAppearance.Parse(appearance));
        }
        if (command is "window_minimize" or "window_toggle_maximize" or "window_close" or "window_is_maximized" or "window_outer_position" or "window_outer_size" or "window_current_monitor") return new(id, command, 0, null, false);
        if (command is "dashboard_snapshot" or "dashboard_visuals" or "glass_settings") return new(id, command, 0, null, false);
        if (command == "queue_action")
        {
            if (!root.TryGetProperty("name", out var nameValue) || nameValue.ValueKind != JsonValueKind.String ||
                !root.TryGetProperty("action", out var actionValue) || actionValue.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Invalid queue request.");
            string name=nameValue.GetString()!;
            string action=actionValue.GetString()!;
            if (name.Length==0 || System.Text.Encoding.UTF8.GetByteCount(name)>256 || action is not ("start_queue" or "stop_queue"))
                throw new InvalidOperationException("Unsupported queue request.");
            return new(id,command,0,null,false,Key:name,Value:action);
        }
        if (command == "file_speed_limit")
        {
            if (!root.TryGetProperty("downloadId", out var item) || !item.TryGetUInt64(out ulong itemId) || itemId == 0 ||
                !root.TryGetProperty("value", out var amount) || !amount.TryGetUInt64(out ulong kb) || kb > 10_000_000)
                throw new InvalidOperationException("Invalid speed limit request.");
            return new(id, command, itemId, null, false, Value: kb.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }
        if (command is "start_download" or "pause_download" or "remove_download" or "file_details" or "file_open" or "file_folder")
        {
            if (!root.TryGetProperty("downloadId", out var downloadId) || !downloadId.TryGetUInt64(out ulong value) || value == 0)
                throw new InvalidOperationException("Invalid download ID.");
            return new(id, command, value, null, false);
        }
        if (command == "update_glass_setting")
        {
            if (!root.TryGetProperty("key", out var keyValue) || keyValue.ValueKind != JsonValueKind.String ||
                !root.TryGetProperty("value", out var settingValue) || settingValue.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Invalid settings change.");
            string key = keyValue.GetString()!;
            string value = settingValue.GetString()!;
            string[] allowed = { "max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb", "start_immediately", "only_add_to_queue", "confirm_delete", "torrent_keep_sharing", "torrent_dht", "torrent_lsd", "proxy_from_browser", "capture_opened", "net_adapter", "show_complete", "show_progress", "advanced_integration", "double_click_open" };
            if (!allowed.Contains(key) || System.Text.Encoding.UTF8.GetByteCount(value) > 256)
                throw new InvalidOperationException("Unsupported settings change.");
            return new(id, command, 0, null, false, key, value);
        }
        if (command == "add_download")
        {
            if (!root.TryGetProperty("url", out var urlValue) || urlValue.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Invalid download link.");
            string url = urlValue.GetString()?.Trim() ?? "";
            if (url.Length == 0 || System.Text.Encoding.UTF8.GetByteCount(url) > 8192 ||
                !(url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("ftp://", StringComparison.Ordinal) || url.StartsWith("magnet:", StringComparison.Ordinal)))
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
