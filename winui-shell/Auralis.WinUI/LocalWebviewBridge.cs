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
    internal static async Task<CoreWebView2Environment> AttachPreviewAsync(WebView2 view, Microsoft.UI.Xaml.Window owner, string assetDirectory, Action<NativeAppearance> applyAppearance, Func<BridgeMessage, JsonElement> windowCommand, Func<BridgeMessage, Task<JsonElement>> openWindow, Func<BridgeMessage, Task<JsonElement>> exportFile, Func<BridgeMessage, Task<JsonElement>> openTestFile, Func<BridgeMessage, Task<JsonElement>> progressTray, bool sandbox=false, CoreWebView2Environment? sharedEnvironment=null)
    {
        if (!Directory.Exists(assetDirectory)) throw new DirectoryNotFoundException("Build the local interface preview assets first.");
        var adapterPath=Path.Combine(assetDirectory,sandbox?"winui-sandbox-compat.js":"winui-preview-compat.js");
        if (!File.Exists(adapterPath) || !File.Exists(Path.Combine(assetDirectory,"index.html"))) throw new FileNotFoundException("Interface preview assets are missing.");
        string localData=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localData) || !Path.IsPathFullyQualified(localData)) throw new InvalidOperationException("The local application data folder is unavailable.");
        string profileRoot=Path.Combine(localData,"Auralis WinUI Development");
        EnsureDevelopmentDirectory(profileRoot);
        var profile=Path.Combine(profileRoot,sandbox?"WebView-Downloads":"WebView-Sample");
        EnsureDevelopmentDirectory(profile);
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
        Windows.Foundation.TypedEventHandler<Microsoft.UI.Windowing.AppWindow,Microsoft.UI.Windowing.AppWindowChangedEventArgs> changed = (_,args) =>
        {
            if (!args.DidPositionChange && !args.DidSizeChange && !args.DidPresenterChange) return;
            try { core.PostWebMessageAsJson("{\"event\":\"window_bounds_changed\"}"); }
            catch (Exception) { /* A view may already be closing or navigating. */ }
        };
        var appWindow=owner.AppWindow;
        appWindow.Changed += changed;
        owner.Closed += (_,_) => appWindow.Changed -= changed;
        core.WebMessageReceived+=async (_,args)=>{
            long? id=null;
            try {
                var message=BridgeMessage.Parse(args.Source,args.WebMessageAsJson);id=message.Id;
                var value=message.Appearance is not null
                    ? ApplyAppearance(message.Appearance,applyAppearance)
                    : message.Command == "clipboard_text"
                        ? await ReadClipboardAsync()
                    : message.Command is "export_theme_file" or "export_material_file"
                        ? await exportFile(message)
                    : sandbox && (message.Command is "progress_hide" or "progress_restore" or "progress_ids" or "progress_preferences")
                        ? await progressTray(message)
                    : sandbox && (message.Command is "file_open" or "file_folder")
                        ? await openTestFile(message)
                    : message.Command == "open_glass_window"
                        ? await openWindow(message)
                    : message.Command is "window_hide" or "window_minimize" or "window_toggle_maximize" or "window_close" or "window_is_maximized" or "window_outer_position" or "window_outer_size" or "window_current_monitor" or "window_start_drag" or "window_start_resize"
                        ? windowCommand(message)
                    : sandbox && (message.Command is "dashboard_snapshot" or "dashboard_visuals" or "glass_settings" or "update_glass_setting" or "start_download" or "pause_download" or "remove_download" or "file_details" or "file_speed_limit" or "queue_action" or "add_download")
                        ? await BridgeDispatcher.DispatchAsync(message)
                        : throw new InvalidOperationException("This isolated host does not support that command.");
                core.PostWebMessageAsJson(JsonSerializer.Serialize(new {id,ok=true,value}));
            } catch(Exception) {
                if(id is not null)core.PostWebMessageAsJson(JsonSerializer.Serialize(new {id,ok=false,error="The isolated request failed."}));
            }
        };
        return environment;
    }

    private static void EnsureDevelopmentDirectory(string path)
    {
        // Do not follow a junction into an installed app profile.
        if (Directory.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint)!=0)
            throw new InvalidOperationException("The development profile cannot be a redirected folder.");
        Directory.CreateDirectory(path);
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint)!=0)
            throw new InvalidOperationException("The development profile cannot be a redirected folder.");
    }

    private static async Task<JsonElement> ReadClipboardAsync()
    {
        var data=Windows.ApplicationModel.DataTransfer.Clipboard.GetContent();
        if (!data.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Text))
            return JsonSerializer.SerializeToElement("");
        string value=await data.GetTextAsync();
        if (value.Length>8192) throw new InvalidOperationException("Clipboard text is too long.");
        return JsonSerializer.SerializeToElement(value);
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
