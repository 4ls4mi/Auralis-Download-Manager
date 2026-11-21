using System.Text.Json;

namespace Auralis.WinUI;

/// Parses the narrow set of commands that the future packaged web interface
/// can ask the native host to perform. The host must also enforce that no
/// untrusted navigation is allowed and must never expose the downloader token.
internal sealed record BridgeMessage(long Id, string Command, ulong DownloadId, string? Url, bool Later, string? Key = null, string? Value = null, NativeAppearance? Appearance = null, string? Label = null, int Width = 0, int Height = 0, bool Clear = false)
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
        if (command == "window_start_resize")
        {
            if (!root.TryGetProperty("direction", out var direction) || direction.ValueKind != JsonValueKind.String)
                throw new InvalidOperationException("Invalid resize direction.");
            string value=direction.GetString()!;
            _=WindowDragPolicy.ResizeEdge(value);
            return new(id,command,0,null,false,Value:value);
        }
        if (command == "progress_preferences")
        {
            if (!root.TryGetProperty("enabled",out var enabled) || enabled.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new InvalidOperationException("Invalid progress preference.");
            return new(id,command,0,null,false,Value:enabled.GetBoolean()?"true":"false");
        }
        if (command == "progress_ids") return new(id,command,0,null,false);
        if (command == "notify_update")
        {
            if (!root.TryGetProperty("version",out var value) || value.ValueKind!=JsonValueKind.String ||
                value.GetString() is not string version || !UpdatePolicy.TryVersion(version,out _))
                throw new InvalidOperationException("Invalid update notification.");
            return new(id,command,0,null,false,Value:version);
        }
        if (command is "app_version" or "update_check") return new(id,command,0,null,false);
        if (command == "clipboard_text") return new(id,command,0,null,false);
        if (command == "window_start_drag") return new(id,command,0,null,false);
        if (command is "window_hide" or "window_minimize" or "window_toggle_maximize" or "window_close" or "window_is_maximized" or "window_outer_position" or "window_outer_size" or "window_current_monitor") return new(id, command, 0, null, false);
        if (command is "dashboard_snapshot" or "dashboard_visuals" or "glass_settings") return new(id, command, 0, null, false);
        if (command is "preferences" or "network_adapters" or "queue_schedules") return new(id,command,0,null,false);
        if (command == "save_schedule")
        {
            if (!root.TryGetProperty("payload",out var payload) || payload.ValueKind!=JsonValueKind.Object)
                throw new InvalidOperationException("Invalid schedule request.");
            string jsonPayload=payload.GetRawText();
            if (System.Text.Encoding.UTF8.GetByteCount(jsonPayload)>8192) throw new InvalidOperationException("Schedule request is too large.");
            return new(id,command,0,null,false,Value:jsonPayload);
        }
        if (command == "update_preference")
        {
            if (!root.TryGetProperty("key",out var key) || key.ValueKind!=JsonValueKind.String ||
                !root.TryGetProperty("value",out var value)) throw new InvalidOperationException("Invalid preference.");
            string name=key.GetString()!;
            string[] booleans={"limiter_on_startup","global_only_active","set_creation_date","mark_downloads","ignore_mtime","many_connections","proxy_http","proxy_https","proxy_ftp","dns_fallback","ftp_passive"};
            string[] choices={"duplicate_action","proxy_mode","dns_mode"};
            string[] strings={"proxy_script","proxy_host","proxy_port","proxy_user","proxy_pass","user_agent","dns_provider","dns_servers","dns_tls_name","dns_doh_url","dns_nextdns_id"};
            if (!(booleans.Contains(name) && value.ValueKind is (JsonValueKind.True or JsonValueKind.False)) &&
                !(choices.Contains(name) && value.ValueKind==JsonValueKind.Number && value.TryGetInt32(out int choice) && choice is >= 0 and <= 3) &&
                !(strings.Contains(name) && value.ValueKind==JsonValueKind.String && value.GetString() is string text && !text.Contains('\0') && System.Text.Encoding.UTF8.GetByteCount(text)<=512))
                throw new InvalidOperationException("Unsupported preference.");
            bool clear=false;
            if (root.TryGetProperty("clear",out var clearValue))
            {
                if (clearValue.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new InvalidOperationException("Invalid clear flag.");
                clear=clearValue.GetBoolean();
            }
            if (clear && name!="proxy_pass") throw new InvalidOperationException("Invalid clear flag.");
            return new(id,command,0,null,false,Key:name,Value:value.GetRawText(),Clear:clear);
        }
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
        if (command == "queue_item_add")
        {
            if (!root.TryGetProperty("downloadId",out var item) || !item.TryGetUInt64(out ulong target) || target==0 ||
                !root.TryGetProperty("name",out var nameValue) || nameValue.ValueKind!=JsonValueKind.String ||
                nameValue.GetString() is not string name || name.Length==0 || System.Text.Encoding.UTF8.GetByteCount(name)>256)
                throw new InvalidOperationException("Invalid queue request.");
            return new(id,command,target,null,false,Key:name);
        }
        if (command == "file_speed_limit")
        {
            if (!root.TryGetProperty("downloadId", out var item) || !item.TryGetUInt64(out ulong itemId) || itemId == 0 ||
                !root.TryGetProperty("value", out var amount) || !amount.TryGetUInt64(out ulong kb) || kb > 10_000_000)
                throw new InvalidOperationException("Invalid speed limit request.");
            return new(id, command, itemId, null, false, Value: kb.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }
        if (command == "refresh_address")
        {
            if (!root.TryGetProperty("downloadId",out var item) || !item.TryGetUInt64(out ulong target) || target==0 ||
                !root.TryGetProperty("value",out var value) || value.ValueKind!=JsonValueKind.String || value.GetString() is not string address ||
                System.Text.Encoding.UTF8.GetByteCount(address)>8192 || !Uri.TryCreate(address,UriKind.Absolute,out var parsed) ||
                parsed.Scheme is not ("http" or "https") || parsed.Host.Length==0)
                throw new InvalidOperationException("Invalid download address.");
            return new(id,command,target,null,false,Value:address);
        }
        if (command == "checksum")
        {
            if (!root.TryGetProperty("downloadId",out var downloadId) || !downloadId.TryGetUInt64(out ulong target) || target==0 ||
                !root.TryGetProperty("value",out var value) || value.ValueKind!=JsonValueKind.String || value.GetString() is not string checksum ||
                checksum.Length is < 1 or > 256 || checksum.Any(c=>!char.IsAscii(c) || char.IsControl(c)))
                throw new InvalidOperationException("Invalid checksum request.");
            return new(id,command,target,null,false,Value:checksum);
        }
        if (command is "start_download" or "pause_download" or "remove_download" or "file_details" or "check_saved" or "check_saved_result" or "checksum_result" or "queue_item_remove" or "file_open" or "file_folder" or "progress_hide" or "progress_restore")
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
