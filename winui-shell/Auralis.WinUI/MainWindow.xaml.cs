using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Windowing;
using Microsoft.Web.WebView2.Core;
using System.Text.Json;

namespace Auralis.WinUI;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        AppWindow.Closing += OnWindowClosing;
        AppWindow.Changed += (_, _) => UpdatePreviewLayout();
        _progressTrayTimer.Tick += async (_,_) => await RefreshProgressTrayAsync();
        _downloadMonitor.Tick += async (_,_) => await RefreshDownloadTransitionsAsync();
        MaterialSelector.ItemsSource = MaterialPolicy.BuiltIns;
        ThemeSelector.ItemsSource = new[] { "Dark", "Light", "Teal", "Amethyst" };
        ThemeSelector.SelectedIndex = 0;
        MaterialSelector.SelectedIndex = 1;
        try
        {
            _tray=new NativeTrayIcon(this,ShowMain,ExitFromTray,menuAction:HandleTrayAction,menuEnabled:TrayActionEnabled);
            KeepInTray.IsEnabled=true;
        }
        catch (Exception error)
        {
            TrayStatus.Text=$"Notification-area icon unavailable: {error.Message}";
        }
        UpdatePreviewLayout();
    }

    private bool _previewReady, _sandboxReady, _sandboxRequested, _closing, _allowClose, _openingSandbox, _openingPreview;
    private readonly DownloaderLifetime _sandbox = new();
    private NativeTrayIcon? _tray, _progressTray;
    private readonly HashSet<ulong> _hiddenProgress = new();
    private readonly DispatcherTimer _progressTrayTimer = new() { Interval=TimeSpan.FromSeconds(2) };
    private bool _refreshingProgressTray;
    private readonly DispatcherTimer _downloadMonitor = new() { Interval=TimeSpan.FromMilliseconds(1200) };
    private readonly DownloadTransitionTracker _transitionTracker = new();
    private bool _refreshingDownloads, _autoProgress=true;
    private int _viewRequest;
    private CoreWebView2Environment? _previewEnvironment, _sandboxEnvironment;
    private sealed class AuxiliaryWindowState
    {
        internal required Window Window { get; init; }
        internal required WebView2 View { get; init; }
        internal required string Route { get; set; }
        internal bool Ready { get; set; }
    }
    private readonly Dictionary<string, AuxiliaryWindowState> _auxiliaryWindows = new();

    private void UpdatePreviewLayout()
    {
        var area=DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Nearest);
        var maximized=AppWindow.Presenter is OverlappedPresenter presenter && presenter.State==OverlappedPresenterState.Maximized;
        var compact=PreviewLayoutPolicy.UseCompactLayout(maximized,AppWindow.Size.Width,area?.WorkArea.Width ?? 0);
        Root.Padding=new Thickness(compact ? 6 : 24);
        Root.RowSpacing=compact ? 6 : 16;
    }

    private async void OnWindowClosing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        if (_allowClose) return;
        args.Cancel=true;
        await RequestCloseAsync(forceExit:false);
    }

    // AppWindow.Closing is not guaranteed for programmatic window destruction.
    // All native and interface exit paths therefore enter this method directly.
    private async Task RequestCloseAsync(bool forceExit)
    {
        if (_closing) return;
        if (WindowClosePolicy.ShouldHide(KeepInTray.IsChecked==true,_tray?.IsAvailable==true,forceExit))
        {
            AppWindow.Hide();
            return;
        }
        _closing=true;
        CloseAuxiliaryWindows();
        try
        {
            if (_sandboxRequested) await _sandbox.StopAsync();
            _tray?.Dispose();
            _allowClose=true;
            Close();
        }
        catch (Exception error)
        {
            _closing=false;
            if (_sandboxReady) _downloadMonitor.Start();
            ShowMain();
            PreviewIntro.Visibility=Visibility.Visible;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            SandboxControls.Visibility=Visibility.Collapsed;
            BackdropStatus.Text=$"The test downloader has not stopped: {error.Message}";
        }
    }

    private void ShowMain()
    {
        AppWindow.Show();
        if (AppWindow.Presenter is OverlappedPresenter presenter && presenter.State==OverlappedPresenterState.Minimized) presenter.Restore();
        Activate();
    }

    private bool TrayActionEnabled(string action) => action switch
    {
        "add" or "start_queue" or "stop_queue" => _sandboxReady && !_closing,
        "settings" => (_sandboxReady || _previewReady) && !_closing,
        _ => false
    };

    private async void HandleTrayAction(string action)
    {
        try
        {
            if (!TrayActionEnabled(action)) return;
            if (action is "start_queue" or "stop_queue")
            {
                var snapshot=await DownloaderBridge.CallAsync(DownloaderBridge.Operation.DownloadList);
                var queues=snapshot.GetProperty("queues");
                if (queues.GetArrayLength()==0) throw new InvalidOperationException("The download queue is unavailable.");
                string name=queues[0].GetProperty("name").GetString() ?? throw new InvalidOperationException("The download queue is unavailable.");
                await DownloaderBridge.QueueActionAsync(name,action=="start_queue");
                return;
            }
            ShowMain();
            bool sandbox=_sandboxReady && SandboxView.Visibility==Visibility.Visible;
            if (action=="add") sandbox=true;
            else if (!sandbox && !_previewReady) sandbox=true;
            var request=action=="add"
                ? new BridgeMessage(1,"open_glass_window",0,"/?add=url",false,Label:"add-url",Width:590,Height:390)
                : new BridgeMessage(1,"open_glass_window",0,"/?settings=1&tab=General",false,Label:"settings",Width:968,Height:765);
            await OpenAuxiliaryAsync(request,sandbox);
        }
        catch (Exception error)
        {
            ShowMain();
            TrayStatus.Text=$"The tray action could not be completed: {error.Message}";
        }
    }

    private async void ExitFromTray() => await RequestCloseAsync(forceExit:true);

    private async void OnSandboxInterface(object sender, RoutedEventArgs args)
    {
        if (_openingSandbox || _closing) return;
        _openingSandbox=true;
        var request=++_viewRequest;
        _sandboxRequested=true;
        try
        {
            await _sandbox.StartAsync();
            if (_closing || request != _viewRequest) return;
            if (!_sandboxReady)
            {
                _sandboxEnvironment=await LocalWebviewBridge.AttachPreviewAsync(SandboxView,this,Path.Combine(AppContext.BaseDirectory,"interface"),ApplyNativeAppearance,ApplyWindowCommand, message => OpenAuxiliaryAsync(message, true), message => ExportAppearanceAsync(this,message),OpenTestFileAsync,ProgressTrayCommandAsync,sandbox:true);
                _sandboxReady=true;
                await RefreshDownloadTransitionsAsync();
                if (!_closing) _downloadMonitor.Start();
            }
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Collapsed;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxControls.Visibility=Visibility.Visible;
            SandboxView.Visibility=Visibility.Visible;
            SandboxView.CoreWebView2.Navigate("https://auralis.local/index.html");
        }
        catch (Exception error)
        {
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Visible;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            SandboxControls.Visibility=Visibility.Collapsed;
            BackdropStatus.Text=$"Isolated downloader unavailable: {error.Message}";
        }
        finally { _openingSandbox=false; }
    }

    private async void OnAddSandbox(object sender, RoutedEventArgs args)
    {
        if (!_sandboxReady || _closing) return;
        SandboxAdd.IsEnabled=false;
        try
        {
            await DownloaderBridge.AddDownloadAsync(SandboxUrl.Text, false);
            SandboxMessage.Text="Test download sent to the isolated downloads folder.";
            SandboxUrl.Text="";
        }
        catch (Exception error) { SandboxMessage.Text=$"Could not add test download: {error.Message}"; }
        finally { SandboxAdd.IsEnabled=true; }
    }

    private async void OnPreviewInterface(object sender, RoutedEventArgs args) => await OpenPreviewAsync(false);
    private async void OnPreviewSettings(object sender, RoutedEventArgs args) => await OpenPreviewAsync(true);

    private async Task OpenPreviewAsync(bool settings)
    {
        if (_openingPreview || _closing) return;
        _openingPreview=true;
        var request=++_viewRequest;
        try
        {
            if (!_previewReady)
            {
                _previewEnvironment=await LocalWebviewBridge.AttachPreviewAsync(InterfaceView,this,Path.Combine(AppContext.BaseDirectory,"interface"),ApplyNativeAppearance,ApplyWindowCommand, message => OpenAuxiliaryAsync(message, false), message => ExportAppearanceAsync(this,message),OpenTestFileAsync,ProgressTrayCommandAsync);
                _previewReady=true;
            }
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            SandboxControls.Visibility=Visibility.Collapsed;
            InterfaceView.Visibility=Visibility.Visible;
            InterfaceView.CoreWebView2.Navigate(settings ? "https://auralis.local/index.html?settings=1&tab=Appearance" : "https://auralis.local/index.html");
        }
        catch (Exception error)
        {
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Visible;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            SandboxControls.Visibility=Visibility.Collapsed;
            BackdropStatus.Text=$"Interface preview unavailable: {error.Message}";
        }
        finally { _openingPreview=false; }
    }

    private static async Task<JsonElement> OpenTestFileAsync(BridgeMessage message)
    {
        bool folder=message.Command=="file_folder";
        var result=await DownloaderBridge.SafeTestPathAsync(message.DownloadId,folder);
        string path=result.GetProperty("path").GetString() ?? throw new InvalidOperationException("The test download is unavailable.");
        bool launched;
        if (folder)
        {
            var target=await Windows.Storage.StorageFolder.GetFolderFromPathAsync(path);
            launched=await Windows.System.Launcher.LaunchFolderAsync(target);
        }
        else
        {
            var target=await Windows.Storage.StorageFile.GetFileFromPathAsync(path);
            launched=await Windows.System.Launcher.LaunchFileAsync(target);
        }
        if (!launched) throw new InvalidOperationException("Windows could not open the test download.");
        return JsonSerializer.SerializeToElement(new { ok=true });
    }

    private static async Task<JsonElement> ExportAppearanceAsync(Window owner, BridgeMessage message)
    {
        if (message.Value is null) throw new InvalidOperationException("No appearance data was provided.");
        var picker=new Windows.Storage.Pickers.FileSavePicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker,WinRT.Interop.WindowNative.GetWindowHandle(owner));
        picker.SuggestedStartLocation=Windows.Storage.Pickers.PickerLocationId.DocumentsLibrary;
        picker.SuggestedFileName=message.Command=="export_theme_file" ? "auralis-theme" : "auralis-material";
        picker.FileTypeChoices.Add("Auralis JSON",new List<string> { ".json" });
        var file=await picker.PickSaveFileAsync();
        if (file is null) return JsonSerializer.SerializeToElement<string?>(null);
        await Windows.Storage.FileIO.WriteTextAsync(file,message.Value);
        return JsonSerializer.SerializeToElement(file.Path);
    }

    private void CloseAuxiliaryWindows()
    {
        foreach (var state in _auxiliaryWindows.Values.ToArray()) state.Window.Close();
        _auxiliaryWindows.Clear();
        _hiddenProgress.Clear();
        _downloadMonitor.Stop();
        _transitionTracker.Reset();
        _progressTrayTimer.Stop();
        _progressTray?.Dispose();
        _progressTray=null;
    }

    private async Task<JsonElement> OpenAuxiliaryAsync(BridgeMessage message, bool sandbox)
    {
        if (_closing) throw new InvalidOperationException("The shell is closing.");
        var environment = sandbox ? _sandboxEnvironment : _previewEnvironment;
        if (environment is null || message.Label is null || message.Url is null)
            throw new InvalidOperationException("The interface is still starting.");
        string key=(sandbox ? "test:" : "sample:") + message.Label;
        if (_auxiliaryWindows.TryGetValue(key, out var existing))
        {
            bool routeChanged=existing.Route!=message.Url;
            existing.Route=message.Url;
            if (routeChanged && existing.Ready) existing.View.CoreWebView2.Navigate(BridgeMessage.TrustedOrigin + existing.Route);
            existing.Window.AppWindow.Show();
            if (existing.Window.AppWindow.Presenter is OverlappedPresenter presenter && presenter.State==OverlappedPresenterState.Minimized) presenter.Restore();
            existing.Window.Activate();
            if (sandbox && message.Label.StartsWith("download-",StringComparison.Ordinal) && ulong.TryParse(message.Label[9..],out var restoredId)) ForgetHiddenProgress(restoredId);
            return JsonSerializer.SerializeToElement(new { opened=true });
        }
        var child=new Window { Title="Auralis — development preview" };
        var root=new Grid { Background=new SolidColorBrush(Windows.UI.Color.FromArgb(0,0,0,0)) };
        var view=new WebView2();
        root.Children.Add(view);
        child.Content=root;
        bool isProgressPicker=message.Label=="tool-progress-tray";
        var cursor=NativeTrayIcon.CursorPosition();
        var area=isProgressPicker
            ? DisplayArea.GetFromPoint(new Windows.Graphics.PointInt32(cursor.X,cursor.Y),DisplayAreaFallback.Nearest)
            : DisplayArea.GetFromWindowId(AppWindow.Id,DisplayAreaFallback.Nearest);
        double scale=(Content as FrameworkElement)?.XamlRoot?.RasterizationScale ?? 1;
        int width=(int)Math.Round(message.Width*scale), height=(int)Math.Round(message.Height*scale);
        if (area is not null)
        {
            width=Math.Min(width,Math.Max(320,area.WorkArea.Width-32));
            height=Math.Min(height,Math.Max(120,area.WorkArea.Height-32));
        }
        child.AppWindow.Resize(new Windows.Graphics.SizeInt32(width,height));
        if (isProgressPicker && area is not null)
        {
            var work=area.WorkArea;
            int x=Math.Clamp(cursor.X-width/2,work.X,Math.Max(work.X,work.X+work.Width-width));
            int y=Math.Clamp(cursor.Y-height-12,work.Y,Math.Max(work.Y,work.Y+work.Height-height));
            child.AppWindow.Move(new Windows.Graphics.PointInt32(x,y));
        }
        var state=new AuxiliaryWindowState { Window=child, View=view, Route=message.Url };
        _auxiliaryWindows.Add(key,state);
        child.Closed += (_,_) => {
            if (_auxiliaryWindows.TryGetValue(key,out var current) && ReferenceEquals(current,state)) _auxiliaryWindows.Remove(key);
            if (sandbox && message.Label.StartsWith("download-",StringComparison.Ordinal) && ulong.TryParse(message.Label[9..],out var id)) ForgetHiddenProgress(id);
        };
        child.Activate();
        try
        {
            await LocalWebviewBridge.AttachPreviewAsync(view,child,Path.Combine(AppContext.BaseDirectory,"interface"),
                appearance => { ApplyAppearance(child,root,appearance); }, message => ApplyWindowCommand(child,message),
                next => OpenAuxiliaryAsync(next,sandbox), message => ExportAppearanceAsync(child,message),OpenTestFileAsync,ProgressTrayCommandAsync,sandbox,environment);
            if (_closing || !_auxiliaryWindows.TryGetValue(key,out var current) || !ReferenceEquals(current,state)) throw new InvalidOperationException("The preview window was closed.");
            state.Ready=true;
            view.CoreWebView2.Navigate(BridgeMessage.TrustedOrigin + state.Route);
            return JsonSerializer.SerializeToElement(new { opened=true });
        }
        catch
        {
            if (_auxiliaryWindows.TryGetValue(key, out var current) && ReferenceEquals(current, state))
            {
                _auxiliaryWindows.Remove(key);
                child.Close();
            }
            throw;
        }
    }

    private async Task RefreshDownloadTransitionsAsync()
    {
        if (_refreshingDownloads || !_sandboxReady || _closing) return;
        _refreshingDownloads=true;
        try
        {
            var snapshotTask=DownloaderBridge.CallAsync(DownloaderBridge.Operation.DownloadList);
            var settingsTask=DownloaderBridge.CallAsync(DownloaderBridge.Operation.Settings);
            await Task.WhenAll(snapshotTask,settingsTask);
            if (_closing) return;
            var settings=await settingsTask;
            bool progress=settings.TryGetProperty("show_progress",out var showProgress) && showProgress.ValueKind==JsonValueKind.True;
            bool complete=settings.TryGetProperty("show_complete",out var showComplete) && showComplete.ValueKind==JsonValueKind.True;
            var snapshot=DownloadSnapshot.FromJson(await snapshotTask);
            var currentIds=snapshot.Downloads.Select(item=>item.Id).ToHashSet();
            foreach (var missing in _hiddenProgress.Where(id=>!currentIds.Contains(id)).ToArray())
            {
                if (_auxiliaryWindows.TryGetValue($"test:download-{missing}",out var stale)) stale.Window.Close();
                ForgetHiddenProgress(missing);
            }
            foreach (var change in _transitionTracker.Observe(snapshot))
            {
                if (_closing) return;
                if (change.Status=="Complete")
                {
                    if (_auxiliaryWindows.TryGetValue($"test:download-{change.Id}",out var existing)) existing.Window.Close();
                    if (complete) await OpenAuxiliaryAsync(new BridgeMessage(1,"open_glass_window",0,$"/?complete={change.Id}",false,Label:$"complete-{change.Id}",Width:720,Height:420),true);
                }
                else if (progress && _autoProgress && !_hiddenProgress.Contains(change.Id))
                    await OpenAuxiliaryAsync(new BridgeMessage(1,"open_glass_window",0,$"/?detail={change.Id}",false,Label:$"download-{change.Id}",Width:760,Height:560),true);
            }
        }
        catch (Exception error)
        {
            if (!_closing) TrayStatus.Text=$"Download status could not be refreshed: {error.Message}";
        }
        finally { _refreshingDownloads=false; }
    }

    private Task<JsonElement> ProgressTrayCommandAsync(BridgeMessage message)
    {
        switch (message.Command)
        {
            case "progress_ids":
                return Task.FromResult(JsonSerializer.SerializeToElement(_hiddenProgress.ToArray()));
            case "progress_preferences":
                _autoProgress=message.Value=="true";
                break;
            case "progress_hide":
                HideProgress(message.DownloadId);
                break;
            case "progress_restore":
                RestoreProgress(message.DownloadId);
                break;
            default: throw new InvalidOperationException("Unsupported progress tray command.");
        }
        return Task.FromResult(JsonSerializer.SerializeToElement<object?>(null));
    }

    private void HideProgress(ulong id)
    {
        if (!_auxiliaryWindows.TryGetValue($"test:download-{id}",out var state))
            throw new InvalidOperationException("The test download window is unavailable.");
        // Do not hide a window unless a working icon can restore it.
        _progressTray ??=new NativeTrayIcon(this,ShowHiddenProgress,ShowHiddenProgress,2,"Auralis download windows",showMenu:false);
        if (!_progressTray.IsAvailable) throw new InvalidOperationException("The download tray icon is unavailable.");
        _hiddenProgress.Add(id);
        state.Window.AppWindow.Hide();
        _progressTrayTimer.Start();
        _=RefreshProgressTrayAsync();
    }

    private void RestoreProgress(ulong id)
    {
        if (!_hiddenProgress.Contains(id) || !_auxiliaryWindows.TryGetValue($"test:download-{id}",out var state))
            throw new InvalidOperationException("The test download window is no longer hidden.");
        state.Window.AppWindow.Show();
        if (state.Window.AppWindow.Presenter is OverlappedPresenter presenter && presenter.State==OverlappedPresenterState.Minimized) presenter.Restore();
        state.Window.Activate();
        ForgetHiddenProgress(id);
    }

    private void ForgetHiddenProgress(ulong id)
    {
        _hiddenProgress.Remove(id);
        if (_hiddenProgress.Count==0)
        {
            _progressTrayTimer.Stop();
            _progressTray?.Dispose();
            _progressTray=null;
        }
        else _=RefreshProgressTrayAsync();
    }

    private async void ShowHiddenProgress()
    {
        try
        {
            if (_hiddenProgress.Count==1) { RestoreProgress(_hiddenProgress.First()); return; }
            if (_hiddenProgress.Count==0) return;
            var point=NativeTrayIcon.CursorPosition();
            var route=$"/?tool=progress-tray&x={point.X}&y={point.Y}";
            await OpenAuxiliaryAsync(new BridgeMessage(1,"open_glass_window",0,route,false,Label:"tool-progress-tray",Width:500,Height:360),true);
        }
        catch (Exception error)
        {
            ShowMain();
            TrayStatus.Text=$"Could not show download windows: {error.Message}";
        }
    }

    private async Task RefreshProgressTrayAsync()
    {
        if (_refreshingProgressTray || _progressTray is null || _hiddenProgress.Count==0) return;
        if (_hiddenProgress.Count>1) { _progressTray.SetTooltip($"Auralis — {_hiddenProgress.Count} download windows"); return; }
        ulong id=_hiddenProgress.First();
        _refreshingProgressTray=true;
        try
        {
            var snapshot=await DownloaderBridge.CallAsync(DownloaderBridge.Operation.DownloadList);
            if (!_hiddenProgress.Contains(id) || _progressTray is null || _hiddenProgress.Count!=1) return;
            var item=DownloadSnapshot.FromJson(snapshot).Downloads.FirstOrDefault(download=>download.Id==id);
            if (item is not null)
            {
                _progressTray.SetTooltip(TrayTooltipPolicy.ForDownload(item));
                return;
            }
            _progressTray.SetTooltip("Auralis — download no longer available");
        }
        catch { _progressTray?.SetTooltip("Auralis — download information unavailable"); }
        finally { _refreshingProgressTray=false; }
    }

    private JsonElement ApplyWindowCommand(BridgeMessage message) => ApplyWindowCommand(this, message);

    private JsonElement ApplyWindowCommand(Window window, BridgeMessage message)
    {
        if (window.AppWindow.Presenter is not OverlappedPresenter presenter)
            throw new InvalidOperationException("The window presenter is unavailable.");
        switch (message.Command)
        {
            case "window_hide":
                if (!ReferenceEquals(window,this) || _tray?.IsAvailable!=true) throw new InvalidOperationException("The notification area is unavailable for this window.");
                AppWindow.Hide();
                break;
            case "window_start_drag": NativeWindowDrag.Start(window,null); break;
            case "window_start_resize": NativeWindowDrag.Start(window,message.Value); break;
            case "window_minimize": presenter.Minimize(); break;
            case "window_toggle_maximize":
                if (presenter.State == OverlappedPresenterState.Maximized) presenter.Restore();
                else presenter.Maximize();
                break;
            case "window_close":
                // Respond before closing. The main window must stop its engine explicitly.
                if (ReferenceEquals(window,this)) window.DispatcherQueue.TryEnqueue(async () => await RequestCloseAsync(forceExit:false));
                else window.DispatcherQueue.TryEnqueue(() => window.Close());
                break;
            case "window_is_maximized":
                return JsonSerializer.SerializeToElement(presenter.State == OverlappedPresenterState.Maximized);
            case "window_outer_position":
                var position=window.AppWindow.Position;
                return JsonSerializer.SerializeToElement(new { x=position.X, y=position.Y });
            case "window_outer_size":
                var size=window.AppWindow.Size;
                return JsonSerializer.SerializeToElement(new { width=size.Width, height=size.Height });
            case "window_current_monitor":
                var display=DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Nearest);
                if (display is null) return JsonSerializer.SerializeToElement<object?>(null);
                var bounds=display.OuterBounds;
                var work=display.WorkArea;
                var scale=(window.Content as FrameworkElement)?.XamlRoot?.RasterizationScale ?? 1;
                return JsonSerializer.SerializeToElement(new {
                    name=(string?)null, scaleFactor=scale,
                    position=new { x=bounds.X, y=bounds.Y }, size=new { width=bounds.Width, height=bounds.Height },
                    workArea=new { position=new { x=work.X, y=work.Y }, size=new { width=work.Width, height=work.Height } }
                });
            default: throw new InvalidOperationException("Unsupported window command.");
        }
        return JsonSerializer.SerializeToElement<object?>(null);
    }

    private void OnThemeChanged(object sender, SelectionChangedEventArgs args) => ApplyMaterial();

    private void OnMaterialChanged(object sender, SelectionChangedEventArgs args) => ApplyMaterial();

    private void ApplyMaterial()
    {
        if (MaterialSelector.SelectedItem is not MaterialDefinition material || ThemeSelector.SelectedItem is not string theme) return;
        var light = theme == "Light";
        var tint = theme switch
        {
            "Light" => (r: (byte)245, g: (byte)245, b: (byte)245),
            "Teal" => (r: (byte)10, g: (byte)91, b: (byte)92),
            "Amethyst" => (r: (byte)68, g: (byte)32, b: (byte)102),
            _ => (r: (byte)14, g: (byte)14, b: (byte)14)
        };
        try { ApplyNativeAppearance(new(material.Id, material.Backdrop, material.OverlayOpacity, tint.r, tint.g, tint.b, light)); }
        catch (System.Exception error) { BackdropStatus.Text = $"Could not apply {material.Label}: {error.Message}"; }
    }

    internal void ApplyNativeAppearance(NativeAppearance appearance)
    {
        bool applied=ApplyAppearance(this, Root, appearance);
        BackdropStatus.Text = applied
            ? $"Requested native Windows {appearance.Backdrop} for {appearance.MaterialId}."
            : "This Windows backdrop is unavailable; using an opaque theme-coloured surface.";
    }

    private static bool ApplyAppearance(Window window, Grid root, NativeAppearance appearance)
    {
        bool supported = appearance.Backdrop switch
        {
            NativeBackdrop.Mica or NativeBackdrop.MicaAlt => MicaController.IsSupported(),
            _ => DesktopAcrylicController.IsSupported()
        };
        root.RequestedTheme = appearance.Light ? ElementTheme.Light : ElementTheme.Dark;
        if (!supported)
        {
            window.SystemBackdrop=null;
            root.Background=new SolidColorBrush(Windows.UI.Color.FromArgb(255,appearance.Red,appearance.Green,appearance.Blue));
            return false;
        }
        window.SystemBackdrop = appearance.Backdrop switch
        {
            NativeBackdrop.Mica => new MicaBackdrop { Kind = MicaKind.Base },
            NativeBackdrop.MicaAlt => new MicaBackdrop { Kind = MicaKind.BaseAlt },
            _ => new DesktopAcrylicBackdrop()
        };
        root.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(appearance.OverlayOpacity, appearance.Red, appearance.Green, appearance.Blue));
        return true;
    }
}
