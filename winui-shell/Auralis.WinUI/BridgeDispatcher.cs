using System.Text.Json;

namespace Auralis.WinUI;

/// Dispatches only messages validated by BridgeMessage. A future WebView host
/// must call Parse with the actual message source before dispatching.
internal static class BridgeDispatcher
{
    internal static Task<JsonElement> DispatchAsync(BridgeMessage message) => message.Command switch
    {
        "dashboard_snapshot" => DownloaderBridge.CallAsync(DownloaderBridge.Operation.DownloadList),
        "dashboard_visuals" => DownloaderBridge.CallAsync(DownloaderBridge.Operation.Visuals),
        "start_download" => DownloaderBridge.StartDownloadAsync(message.DownloadId),
        "pause_download" => DownloaderBridge.PauseDownloadAsync(message.DownloadId),
        "add_download" when message.Url is not null => DownloaderBridge.AddDownloadAsync(message.Url, message.Later),
        _ => throw new InvalidOperationException("Unsupported interface command.")
    };
}
