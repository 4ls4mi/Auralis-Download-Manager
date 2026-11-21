using System.Runtime.InteropServices;
using System.Text.Json;

namespace Auralis.WinUI;

/// Narrow, asynchronous boundary to the Rust downloader. The preview does not
/// invoke it yet; data-folder migration and lifecycle must be validated first.
internal static class DownloaderBridge
{
    internal enum Operation : uint { Start = 1, Stop = 2, DownloadList = 3, Visuals = 4 }

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_call(Operation operation);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr auralis_bridge_download_action(uint action, ulong id);

    [DllImport("auralis_winui_bridge", CallingConvention = CallingConvention.Cdecl)]
    private static extern void auralis_bridge_free(IntPtr response);

    internal static Task<JsonElement> CallAsync(Operation operation) => Task.Run(() => ReadResponse(auralis_bridge_call(operation)));
    internal static Task<JsonElement> StartDownloadAsync(ulong id) => Task.Run(() => ReadResponse(auralis_bridge_download_action(1, id)));
    internal static Task<JsonElement> PauseDownloadAsync(ulong id) => Task.Run(() => ReadResponse(auralis_bridge_download_action(2, id)));

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
