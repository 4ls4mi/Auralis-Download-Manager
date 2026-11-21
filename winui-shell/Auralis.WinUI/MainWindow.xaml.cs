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
        MaterialSelector.ItemsSource = MaterialPolicy.BuiltIns;
        ThemeSelector.ItemsSource = new[] { "Dark", "Light", "Teal", "Amethyst" };
        ThemeSelector.SelectedIndex = 0;
        MaterialSelector.SelectedIndex = 1;
    }

    private bool _previewReady, _sandboxReady, _sandboxRequested, _closing, _allowClose, _openingSandbox, _openingPreview;
    private readonly DownloaderLifetime _sandbox = new();
    private int _viewRequest;
    private CoreWebView2Environment? _previewEnvironment, _sandboxEnvironment;
    private readonly Dictionary<string, Window> _auxiliaryWindows = new();

    private async void OnWindowClosing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        if (_allowClose) return;
        if (!_sandboxRequested) { _closing=true; CloseAuxiliaryWindows(); return; }
        args.Cancel=true;
        if (_closing) return;
        _closing=true;
        CloseAuxiliaryWindows();
        try
        {
            await _sandbox.StopAsync();
            _allowClose=true;
            Close();
        }
        catch (Exception error)
        {
            _closing=false;
            PreviewIntro.Visibility=Visibility.Visible;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            SandboxControls.Visibility=Visibility.Collapsed;
            BackdropStatus.Text=$"The test downloader has not stopped: {error.Message}";
        }
    }

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
                _sandboxEnvironment=await LocalWebviewBridge.AttachPreviewAsync(SandboxView,Path.Combine(AppContext.BaseDirectory,"interface"),ApplyNativeAppearance,ApplyWindowCommand, message => OpenAuxiliaryAsync(message, true), message => ExportAppearanceAsync(this,message),sandbox:true);
                _sandboxReady=true;
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
                _previewEnvironment=await LocalWebviewBridge.AttachPreviewAsync(InterfaceView,Path.Combine(AppContext.BaseDirectory,"interface"),ApplyNativeAppearance,ApplyWindowCommand, message => OpenAuxiliaryAsync(message, false), message => ExportAppearanceAsync(this,message));
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
        foreach (var window in _auxiliaryWindows.Values.ToArray()) window.Close();
        _auxiliaryWindows.Clear();
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
            existing.Activate();
            return JsonSerializer.SerializeToElement(new { opened=true });
        }
        var child=new Window { Title="Auralis — development preview" };
        var root=new Grid { Background=new SolidColorBrush(Windows.UI.Color.FromArgb(0,0,0,0)) };
        var view=new WebView2();
        root.Children.Add(view);
        child.Content=root;
        child.AppWindow.Resize(new Windows.Graphics.SizeInt32(message.Width,message.Height));
        _auxiliaryWindows.Add(key,child);
        child.Closed += (_,_) => _auxiliaryWindows.Remove(key);
        child.Activate();
        try
        {
            await LocalWebviewBridge.AttachPreviewAsync(view,Path.Combine(AppContext.BaseDirectory,"interface"),
                appearance => { ApplyAppearance(child,root,appearance); }, command => ApplyWindowCommand(child,command),
                next => OpenAuxiliaryAsync(next,sandbox), message => ExportAppearanceAsync(child,message),sandbox,environment);
            if (_closing || !_auxiliaryWindows.ContainsKey(key)) throw new InvalidOperationException("The preview window was closed.");
            view.CoreWebView2.Navigate(BridgeMessage.TrustedOrigin + message.Url);
            return JsonSerializer.SerializeToElement(new { opened=true });
        }
        catch
        {
            if (_auxiliaryWindows.TryGetValue(key, out var current) && ReferenceEquals(current, child))
            {
                _auxiliaryWindows.Remove(key);
                child.Close();
            }
            throw;
        }
    }

    private JsonElement ApplyWindowCommand(string command) => ApplyWindowCommand(this, command);

    private static JsonElement ApplyWindowCommand(Window window, string command)
    {
        if (window.AppWindow.Presenter is not OverlappedPresenter presenter)
            throw new InvalidOperationException("The window presenter is unavailable.");
        switch (command)
        {
            case "window_minimize": presenter.Minimize(); break;
            case "window_toggle_maximize":
                if (presenter.State == OverlappedPresenterState.Maximized) presenter.Restore();
                else presenter.Maximize();
                break;
            case "window_close":
                // Respond before closing; the normal shutdown handler stops the test engine.
                window.DispatcherQueue.TryEnqueue(() => window.Close());
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
