using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

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

    private async void OnWindowClosing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        if (_allowClose) return;
        if (!_sandboxRequested) { _closing=true; return; }
        args.Cancel=true;
        if (_closing) return;
        _closing=true;
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
                await LocalWebviewBridge.AttachPreviewAsync(SandboxView,Path.Combine(AppContext.BaseDirectory,"interface"),ApplyNativeAppearance,sandbox:true);
                _sandboxReady=true;
            }
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Collapsed;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Visible;
            SandboxView.CoreWebView2.Navigate("https://auralis.local/index.html");
        }
        catch (Exception error)
        {
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Visible;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            BackdropStatus.Text=$"Isolated downloader unavailable: {error.Message}";
        }
        finally { _openingSandbox=false; }
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
                await LocalWebviewBridge.AttachPreviewAsync(InterfaceView,Path.Combine(AppContext.BaseDirectory,"interface"),ApplyNativeAppearance);
                _previewReady=true;
            }
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            InterfaceView.Visibility=Visibility.Visible;
            InterfaceView.CoreWebView2.Navigate(settings ? "https://auralis.local/index.html?settings=1&tab=Appearance" : "https://auralis.local/index.html");
        }
        catch (Exception error)
        {
            if (_closing || request != _viewRequest) return;
            PreviewIntro.Visibility=Visibility.Visible;
            InterfaceView.Visibility=Visibility.Collapsed;
            SandboxView.Visibility=Visibility.Collapsed;
            BackdropStatus.Text=$"Interface preview unavailable: {error.Message}";
        }
        finally { _openingPreview=false; }
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

    // Used by the local WebView host when the real interface is connected.
    internal void ApplyNativeAppearance(NativeAppearance appearance)
    {
        try
        {
            bool supported = appearance.Backdrop switch
            {
                NativeBackdrop.Mica or NativeBackdrop.MicaAlt => MicaController.IsSupported(),
                _ => DesktopAcrylicController.IsSupported()
            };
            if (!supported) throw new System.InvalidOperationException("This Windows system does not support the requested backdrop.");
            SystemBackdrop = appearance.Backdrop switch
            {
                NativeBackdrop.Mica => new MicaBackdrop { Kind = MicaKind.Base },
                NativeBackdrop.MicaAlt => new MicaBackdrop { Kind = MicaKind.BaseAlt },
                _ => new DesktopAcrylicBackdrop()
            };
            Root.RequestedTheme = appearance.Light ? ElementTheme.Light : ElementTheme.Dark;
            Root.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(appearance.OverlayOpacity, appearance.Red, appearance.Green, appearance.Blue));
            BackdropStatus.Text = $"Requested native Windows {appearance.Backdrop} for {appearance.MaterialId}.";
        }
        catch
        {
            SystemBackdrop = null;
            throw;
        }
    }
}
