using System.Text.Json;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace Auralis.WinUI;

/// Development bridge for packaged local UI assets. This is not wired into the
/// preview yet: lifecycle, full command parity and data migration remain open.
internal static class LocalWebviewBridge
{
    internal static async Task AttachAsync(WebView2 view, string assetDirectory)
    {
        if (!Directory.Exists(assetDirectory)) throw new DirectoryNotFoundException("Packaged interface assets are missing.");
        await view.EnsureCoreWebView2Async();
        view.DefaultBackgroundColor = Windows.UI.Color.FromArgb(0, 0, 0, 0);
        var core = view.CoreWebView2 ?? throw new InvalidOperationException("WebView2 is unavailable.");
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreHostObjectsAllowed = false;
        core.SetVirtualHostNameToFolderMapping("auralis.local", Path.GetFullPath(assetDirectory), CoreWebView2HostResourceAccessKind.DenyCors);
        core.NavigationStarting += (_, args) =>
        {
            if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
                uri.Host != "auralis.local" || !uri.IsDefaultPort || uri.UserInfo.Length != 0)
                args.Cancel = true;
        };
        core.NewWindowRequested += (_, args) => args.Handled = true;
        core.WebMessageReceived += async (_, args) =>
        {
            long? requestId = null;
            try
            {
                var message = BridgeMessage.Parse(args.Source, args.WebMessageAsJson);
                requestId = message.Id;
                var value = await BridgeDispatcher.DispatchAsync(message);
                core.PostWebMessageAsJson(JsonSerializer.Serialize(new { id = requestId, ok = true, value }));
            }
            catch (Exception)
            {
                // Do not disclose file paths, credentials, or parser details to
                // an untrusted/invalid sender. The host must log actionable errors separately.
                if (requestId is not null)
                    core.PostWebMessageAsJson(JsonSerializer.Serialize(new { id = requestId, ok = false, error = "The requested operation could not be completed." }));
            }
        };
    }
}
