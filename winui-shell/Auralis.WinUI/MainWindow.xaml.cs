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
        MaterialSelector.ItemsSource = new[] { "Acrylic", "Mica", "Mica Alt" };
        MaterialSelector.SelectedIndex = 0;
    }

    private void OnMaterialChanged(object sender, SelectionChangedEventArgs args)
    {
        if (MaterialSelector.SelectedItem is not string material) return;
        try
        {
            SystemBackdrop = material switch
            {
                "Mica" => new MicaBackdrop { Kind = MicaKind.Base },
                "Mica Alt" => new MicaBackdrop { Kind = MicaKind.BaseAlt },
                _ => new DesktopAcrylicBackdrop()
            };
            BackdropStatus.Text = $"Requested native Windows {material}.";
        }
        catch (System.Exception error)
        {
            SystemBackdrop = null;
            BackdropStatus.Text = $"Could not apply {material}: {error.Message}";
        }
    }
}
