namespace Auralis.WinUI;

/// Keeps the preview frame compact when maximized or confined to a narrow
/// portion of the current monitor. Dimensions are physical Windows pixels.
internal static class PreviewLayoutPolicy
{
    internal static bool UseCompactLayout(bool maximized, int windowWidth, int workAreaWidth) =>
        maximized || (windowWidth > 0 && workAreaWidth > 0 && (long)windowWidth * 10 <= (long)workAreaWidth * 7);
}
