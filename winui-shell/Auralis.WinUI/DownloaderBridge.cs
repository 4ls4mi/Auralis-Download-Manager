using System.Runtime.InteropServices;
using System.Text.Json;

namespace Auralis.WinUI;

/// Narrow, asynchronous boundary to the Rust downloader. The preview does not
/// invoke it yet; data-folder migration and lifecycle must be validated first.
internal static class DownloaderBridge
{
    internal enum Operation : uint { Start = 1, Stop = 2, DownloadList = 3, Visuals = 4, Settings = 5, InitializeSandbox = 6, InitializeDevelopmentProfile = 7, Preferences = 8, NetworkAdapters = 9 }

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_call(Operation operation);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_download_action(uint action, ulong id);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_queue_action(byte[] name, nuint length, byte action);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_item_queue_action(ulong id, byte[] name, nuint length);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_file_details(ulong id);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_check_saved(ulong id, byte result);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_checksum(ulong id, byte[] input, nuint length);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_refresh_address(ulong id, byte[] input, nuint length);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_safe_test_path(ulong id, byte folder);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_speed_limit(ulong id, ulong kb);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_add_download(byte[] url, nuint length, byte later);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_update_setting(byte[] input, nuint length);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_update_preference(byte[] input, nuint length);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern void auralis_bridge_free(IntPtr response);

    internal static Task<JsonElement> CallAsync(Operation operation) => Task.Run(() => ReadResponse(auralis_bridge_call(operation)));
    internal static Task<JsonElement> QueueActionAsync(string name, bool start) => Task.Run(() =>
    {
        byte[] bytes = System.Text.Encoding.UTF8.GetBytes(name);
        return ReadResponse(auralis_bridge_queue_action(bytes, (nuint)bytes.Length, start ? (byte)1 : (byte)2));
    });
    internal static Task<JsonElement> ItemQueueActionAsync(ulong id, string? name) => Task.Run(() =>
    {
        byte[] bytes=System.Text.Encoding.UTF8.GetBytes(name ?? "");
        return ReadResponse(auralis_bridge_item_queue_action(id,bytes,(nuint)bytes.Length));
    });
    internal static Task<JsonElement> FileDetailsAsync(ulong id) => Task.Run(() => ReadResponse(auralis_bridge_file_details(id)));
    internal static Task<JsonElement> CheckSavedAsync(ulong id, bool result) => Task.Run(() => ReadResponse(auralis_bridge_check_saved(id,result ? (byte)1 : (byte)0)));
    internal static Task<JsonElement> ChecksumAsync(ulong id, string? expected) => Task.Run(() =>
    {
        byte[] bytes=System.Text.Encoding.UTF8.GetBytes(expected ?? "");
        return ReadResponse(auralis_bridge_checksum(id,bytes,(nuint)bytes.Length));
    });
    internal static Task<JsonElement> RefreshAddressAsync(ulong id, string address) => Task.Run(() =>
    {
        byte[] bytes=System.Text.Encoding.UTF8.GetBytes(address);
        return ReadResponse(auralis_bridge_refresh_address(id,bytes,(nuint)bytes.Length));
    });
    internal static Task<JsonElement> SafeTestPathAsync(ulong id, bool folder) => Task.Run(() => ReadResponse(auralis_bridge_safe_test_path(id, folder ? (byte)1 : (byte)0)));
    internal static Task<JsonElement> SpeedLimitAsync(ulong id, ulong kb) => Task.Run(() => ReadResponse(auralis_bridge_speed_limit(id, kb)));
    internal static Task<JsonElement> StartDownloadAsync(ulong id) => Task.Run(() => ReadResponse(auralis_bridge_download_action(1, id)));
    internal static Task<JsonElement> RemoveDownloadAsync(ulong id) => Task.Run(() => ReadResponse(auralis_bridge_download_action(3, id)));
    internal static Task<JsonElement> PauseDownloadAsync(ulong id) => Task.Run(() => ReadResponse(auralis_bridge_download_action(2, id)));
    internal static Task<JsonElement> AddDownloadAsync(string url, bool later) => Task.Run(() =>
    {
        byte[] bytes = System.Text.Encoding.UTF8.GetBytes(url);
        return ReadResponse(auralis_bridge_add_download(bytes, (nuint)bytes.Length, later ? (byte)1 : (byte)0));
    });

    internal static Task<JsonElement> UpdateSettingAsync(string key, string value) => Task.Run(() =>
    {
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(new { key, value });
        return ReadResponse(auralis_bridge_update_setting(bytes, (nuint)bytes.Length));
    });

    internal static Task<JsonElement> UpdatePreferenceAsync(string key, string value, bool clear) => Task.Run(() =>
    {
        using var parsed=JsonDocument.Parse(value);
        byte[] bytes=JsonSerializer.SerializeToUtf8Bytes(new { key, value=parsed.RootElement, clear });
        return ReadResponse(auralis_bridge_update_preference(bytes,(nuint)bytes.Length));
    });

    private static JsonElement ReadResponse(IntPtr response)
    {
        if (response == IntPtr.Zero) throw new InvalidOperationException("The downloader bridge returned no response.");
        try
        {
            string json = Marshal.PtrToStringUTF8(response) ?? throw new InvalidOperationException("The downloader response was not UTF-8.");
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            if (!root.GetProperty("ok").GetBoolean()) throw new InvalidOperationException(root.GetProperty("error").GetString() ?? "Downloader request failed.");
            return root.GetProperty("value").Clone();
        }
        finally { auralis_bridge_free(response); }
    }
}
