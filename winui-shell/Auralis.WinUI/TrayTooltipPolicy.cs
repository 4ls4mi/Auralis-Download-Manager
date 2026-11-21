using System.Globalization;

namespace Auralis.WinUI;

/// Formats the notification-area tooltip without changing download state.
internal static class TrayTooltipPolicy
{
    internal static string ForDownload(DownloadEntry item)
    {
        string progress=item.Progress is double value ? value.ToString("0.0",CultureInfo.CurrentCulture)+"%" : "size unknown";
        string speed=(item.Speed/1048576d).ToString("0.00",CultureInfo.CurrentCulture)+" MB/s";
        string time="";
        if (item.Size is > 0 && item.Downloaded<item.Size.Value && item.Speed>0)
        {
            ulong seconds=(item.Size.Value-item.Downloaded)/item.Speed;
            time=seconds<60 ? $" · {seconds}s left" : seconds<3600 ? $" · {seconds/60}m left" : $" · {seconds/3600}h left";
        }
        return $"{item.File} — {item.Status} · {progress} · {speed}{time}";
    }

    internal static string Clamp(string value)
    {
        if (value.Length<=127) return value;
        int length=char.IsHighSurrogate(value[126]) ? 126 : 127;
        return value[..length];
    }
}
