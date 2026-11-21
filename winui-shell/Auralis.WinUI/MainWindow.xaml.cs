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
        MaterialSelector.ItemsSource = MaterialPolicy.BuiltIns;
        ThemeSelector.ItemsSource = new[] { "Dark", "Light", "Teal", "Amethyst" };
        ThemeSelector.SelectedIndex = 0;
        MaterialSelector.SelectedIndex = 1;
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
