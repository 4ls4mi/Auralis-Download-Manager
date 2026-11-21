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
        ThemeSelector.ItemsSource = new[] { "Dark", "Light" };
        ThemeSelector.SelectedIndex = 0;
        MaterialSelector.SelectedIndex = 1;
    }

    private void OnThemeChanged(object sender, SelectionChangedEventArgs args) => ApplyMaterial();

    private void OnMaterialChanged(object sender, SelectionChangedEventArgs args) => ApplyMaterial();

    private void ApplyMaterial()
    {
        if (MaterialSelector.SelectedItem is not MaterialDefinition material || ThemeSelector.SelectedItem is not string theme) return;
        try
        {
            SystemBackdrop = material.Backdrop switch
            {
                NativeBackdrop.Mica => new MicaBackdrop { Kind = MicaKind.Base },
                NativeBackdrop.MicaAlt => new MicaBackdrop { Kind = MicaKind.BaseAlt },
                _ => new DesktopAcrylicBackdrop()
            };
            var light = theme == "Light";
            Root.RequestedTheme = light ? ElementTheme.Light : ElementTheme.Dark;
            byte value = light ? (byte)245 : (byte)14;
            Root.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(material.OverlayOpacity, value, value, value));
            BackdropStatus.Text = $"Requested native Windows {material.Backdrop} for {material.Label}.";
        }
        catch (System.Exception error)
        {
            SystemBackdrop = null;
            BackdropStatus.Text = $"Could not apply {material.Label}: {error.Message}";
        }
    }
}
