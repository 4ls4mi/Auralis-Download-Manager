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

/// Appearance passed by the local interface: the theme owns the tint; the
/// material owns the Windows effect. Only bounded declarative values are used.
internal sealed record NativeAppearance(string MaterialId, NativeBackdrop Backdrop, byte OverlayOpacity, byte Red, byte Green, byte Blue, bool Light)
{
    internal static NativeAppearance Parse(System.Text.Json.JsonElement root)
    {
        if (root.ValueKind != System.Text.Json.JsonValueKind.Object ||
            !root.TryGetProperty("material", out var material) || material.ValueKind != System.Text.Json.JsonValueKind.String ||
            !root.TryGetProperty("tint", out var tint) || tint.ValueKind != System.Text.Json.JsonValueKind.Array || tint.GetArrayLength() != 3 ||
            !root.TryGetProperty("light", out var light) || light.ValueKind is not (System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False))
            throw new InvalidOperationException("Invalid appearance request.");
        string id = material.GetString()!;
        byte[] rgb = tint.EnumerateArray().Select(x => x.TryGetByte(out byte value) ? value : throw new InvalidOperationException("Invalid theme tint.")).ToArray();
        var preset = MaterialPolicy.BuiltIns.FirstOrDefault(m => m.Id == id);
        if (preset is not null) return new(id, preset.Backdrop, preset.OverlayOpacity, rgb[0], rgb[1], rgb[2], light.GetBoolean());
        if (!id.StartsWith("custom-", StringComparison.Ordinal) || id.Length > 407 || id.Length <= 7 || (id.Length - 7) % 2 != 0 || !id[7..].All(Uri.IsHexDigit) ||
            !root.TryGetProperty("finish", out var finish) || finish.ValueKind != System.Text.Json.JsonValueKind.String ||
            !root.TryGetProperty("translucency", out var translucency) || !translucency.TryGetDouble(out double amount) || !double.IsFinite(amount) || amount < 0 || amount > 100)
            throw new InvalidOperationException("Unsupported custom material.");
        var backdrop = finish.GetString() switch
        {
            "matte" => NativeBackdrop.Mica,
            "satin" or "gloss" or "frosted" or "clear" => NativeBackdrop.Acrylic,
            _ => throw new InvalidOperationException("Unsupported material finish.")
        };
        byte opacity = (byte)Math.Round(16 + (100 - amount) * .45);
        return new(id, backdrop, opacity, rgb[0], rgb[1], rgb[2], light.GetBoolean());
    }
}
