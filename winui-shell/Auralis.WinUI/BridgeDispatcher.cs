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
        "glass_settings" => DownloaderBridge.CallAsync(DownloaderBridge.Operation.Settings),
        "update_glass_setting" when message.Key is not null && message.Value is not null => DownloaderBridge.UpdateSettingAsync(message.Key, message.Value),
        "queue_action" when message.Key is not null && message.Value is not null => DownloaderBridge.QueueActionAsync(message.Key, message.Value == "start_queue"),
        "file_speed_limit" when message.Value is not null => DownloaderBridge.SpeedLimitAsync(message.DownloadId, ulong.Parse(message.Value, System.Globalization.CultureInfo.InvariantCulture)),
        "file_details" => DownloaderBridge.FileDetailsAsync(message.DownloadId),
        "start_download" => DownloaderBridge.StartDownloadAsync(message.DownloadId),
        "remove_download" => DownloaderBridge.RemoveDownloadAsync(message.DownloadId),
        "pause_download" => DownloaderBridge.PauseDownloadAsync(message.DownloadId),
        "add_download" when message.Url is not null => DownloaderBridge.AddDownloadAsync(message.Url, message.Later),
        _ => throw new InvalidOperationException("Unsupported interface command.")
    };
}
