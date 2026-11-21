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
        "preferences" => DownloaderBridge.CallAsync(DownloaderBridge.Operation.Preferences),
        "network_adapters" => DownloaderBridge.CallAsync(DownloaderBridge.Operation.NetworkAdapters),
        "update_preference" when message.Key is not null && message.Value is not null => DownloaderBridge.UpdatePreferenceAsync(message.Key,message.Value,message.Clear),
        "update_glass_setting" when message.Key is not null && message.Value is not null => DownloaderBridge.UpdateSettingAsync(message.Key, message.Value),
        "queue_action" when message.Key is not null && message.Value is not null => DownloaderBridge.QueueActionAsync(message.Key, message.Value == "start_queue"),
        "file_speed_limit" when message.Value is not null => DownloaderBridge.SpeedLimitAsync(message.DownloadId, ulong.Parse(message.Value, System.Globalization.CultureInfo.InvariantCulture)),
        "file_details" => DownloaderBridge.FileDetailsAsync(message.DownloadId),
        "check_saved" => DownloaderBridge.CheckSavedAsync(message.DownloadId,false),
        "check_saved_result" => DownloaderBridge.CheckSavedAsync(message.DownloadId,true),
        "checksum" when message.Value is not null => DownloaderBridge.ChecksumAsync(message.DownloadId,message.Value),
        "checksum_result" => DownloaderBridge.ChecksumAsync(message.DownloadId,null),
        "refresh_address" when message.Value is not null => DownloaderBridge.RefreshAddressAsync(message.DownloadId,message.Value),
        "start_download" => DownloaderBridge.StartDownloadAsync(message.DownloadId),
        "remove_download" => DownloaderBridge.RemoveDownloadAsync(message.DownloadId),
        "pause_download" => DownloaderBridge.PauseDownloadAsync(message.DownloadId),
        "add_download" when message.Url is not null => DownloaderBridge.AddDownloadAsync(message.Url, message.Later),
        _ => throw new InvalidOperationException("Unsupported interface command.")
    };
}
