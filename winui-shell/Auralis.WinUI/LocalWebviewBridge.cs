using System.Text.Json;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace Auralis.WinUI;

/// Development bridge for local UI assets. Production command parity,
/// lifecycle and data migration remain open.
internal static class LocalWebviewBridge
{
    private static JsonElement ApplyAppearance(NativeAppearance appearance, Action<NativeAppearance> apply)
    {
        apply(appearance);
        return JsonSerializer.SerializeToElement(new { applied = true });
    }

    /// Isolated WebView profiles keep sample and test interfaces separate from
    /// installed settings and downloads; auxiliary views share their parent profile.
    internal static async Task<CoreWebView2Environment> AttachPreviewAsync(WebView2 view, string assetDirectory, Action<NativeAppearance> applyAppearance, Func<string, JsonElement> windowCommand, Func<BridgeMessage, Task<JsonElement>> openWindow, Func<BridgeMessage, Task<JsonElement>> exportFile, bool sandbox=false, CoreWebView2Environment? sharedEnvironment=null)
    {
        if (!Directory.Exists(assetDirectory)) throw new DirectoryNotFoundException("Build the local interface preview assets first.");
        var adapterPath=Path.Combine(assetDirectory,sandbox?"winui-sandbox-compat.js":"winui-preview-compat.js");
        if (!File.Exists(adapterPath) || !File.Exists(Path.Combine(assetDirectory,"index.html"))) throw new FileNotFoundException("Interface preview assets are missing.");
        var profile=Path.Combine(Path.GetTempPath(),"auralis-winui-preview-"+Guid.NewGuid().ToString("N"));
        var environment=sharedEnvironment ?? await CoreWebView2Environment.CreateWithOptionsAsync(null, profile, null);
        await view.EnsureCoreWebView2Async(environment);
        view.DefaultBackgroundColor=Windows.UI.Color.FromArgb(0,0,0,0);
        var core=view.CoreWebView2 ?? throw new InvalidOperationException("WebView2 is unavailable.");
        core.Settings.AreDevToolsEnabled=false;
        core.Settings.AreHostObjectsAllowed=false;
        core.Settings.AreDefaultScriptDialogsEnabled=false;
        core.SetVirtualHostNameToFolderMapping("auralis.local",Path.GetFullPath(assetDirectory),CoreWebView2HostResourceAccessKind.DenyCors);
        core.NavigationStarting+=(_,args)=>{if(!IsLocal(args.Uri))args.Cancel=true;};
        core.NewWindowRequested+=(_,args)=>args.Handled=true;
        core.AddWebResourceRequestedFilter("*",CoreWebView2WebResourceContext.All);
        core.WebResourceRequested+=(_,args)=>{if(!IsLocal(args.Request.Uri))args.Response=environment.CreateWebResourceResponse(new Windows.Storage.Streams.InMemoryRandomAccessStream(),403,"Blocked","Content-Type: text/plain");};
        await core.AddScriptToExecuteOnDocumentCreatedAsync(await File.ReadAllTextAsync(adapterPath));
        core.WebMessageReceived+=async (_,args)=>{
            long? id=null;
            try {
                var message=BridgeMessage.Parse(args.Source,args.WebMessageAsJson);id=message.Id;
                var value=message.Appearance is not null
                    ? ApplyAppearance(message.Appearance,applyAppearance)
                    : message.Command is "export_theme_file" or "export_material_file"
                        ? await exportFile(message)
                    : message.Command == "open_glass_window"
                        ? await openWindow(message)
                    : message.Command is "window_minimize" or "window_toggle_maximize" or "window_close" or "window_is_maximized" or "window_outer_position" or "window_outer_size" or "window_current_monitor"
                        ? windowCommand(message.Command)
                    : sandbox && (message.Command is "dashboard_snapshot" or "dashboard_visuals" or "glass_settings" or "update_glass_setting" or "start_download" or "pause_download" or "file_details" or "file_speed_limit" or "queue_action")
                        ? await BridgeDispatcher.DispatchAsync(message)
                        : throw new InvalidOperationException("This isolated host does not support that command.");
                core.PostWebMessageAsJson(JsonSerializer.Serialize(new {id,ok=true,value}));
            } catch(Exception) {
                if(id is not null)core.PostWebMessageAsJson(JsonSerializer.Serialize(new {id,ok=false,error="The isolated request failed."}));
            }
        };
        return environment;
    }

    private static bool IsLocal(string address) => Uri.TryCreate(address,UriKind.Absolute,out var uri) &&
        uri.Scheme==Uri.UriSchemeHttps && uri.Host=="auralis.local" && uri.IsDefaultPort && uri.UserInfo.Length==0;

    internal static async Task AttachAsync(WebView2 view, string assetDirectory, Action<NativeAppearance> applyAppearance)
    {
        if (!Directory.Exists(assetDirectory)) throw new DirectoryNotFoundException("Packaged interface assets are missing.");
        string adapterPath = Path.Combine(assetDirectory, "winui-compat.js");
        if (!File.Exists(adapterPath)) throw new FileNotFoundException("The WinUI interface adapter is missing.");
        string adapter = await File.ReadAllTextAsync(adapterPath);
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
        await core.AddScriptToExecuteOnDocumentCreatedAsync(adapter);
        core.WebMessageReceived += async (_, args) =>
        {
            long? requestId = null;
            try
            {
                var message = BridgeMessage.Parse(args.Source, args.WebMessageAsJson);
                requestId = message.Id;
                var value = message.Appearance is not null
                    ? ApplyAppearance(message.Appearance, applyAppearance)
                    : await BridgeDispatcher.DispatchAsync(message);
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
        core.Navigate("https://auralis.local/index.html");
    }
}
