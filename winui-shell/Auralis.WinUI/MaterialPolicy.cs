namespace Auralis.WinUI;

/// Native backdrop is a window-level choice. The theme supplies the overlay
/// colour, while the selected material supplies its strength and backdrop.
internal enum NativeBackdrop { Acrylic, Mica, MicaAlt }
internal sealed record MaterialDefinition(string Id, string Label, NativeBackdrop Backdrop, byte OverlayOpacity);

internal static class MaterialPolicy
{
    internal static readonly MaterialDefinition[] BuiltIns =
    {
        new("brushed-glass", "Brushed Glass · Acrylic", NativeBackdrop.Acrylic, 34),
        new("frosted-water-351", "Frosted Layers · Acrylic", NativeBackdrop.Acrylic, 46),
        new("rose-pine", "Rose Pine · Mica", NativeBackdrop.Mica, 36),
        new("window-glass", "Window Glass · Acrylic", NativeBackdrop.Acrylic, 20),
        new("oversimplified", "Oversimplified · Mica Alt", NativeBackdrop.MicaAlt, 26),
        new("builtin-obsidian-matte", "Matte Obsidian · Mica", NativeBackdrop.Mica, 50),
        new("builtin-smoked-glass", "Smoked Glass · Acrylic", NativeBackdrop.Acrylic, 54),
        new("builtin-pearl-frost", "Pearl Frost · Acrylic", NativeBackdrop.Acrylic, 38),
    };
}
