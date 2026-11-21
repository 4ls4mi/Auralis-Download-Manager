namespace Auralis.WinUI;

/// Maps the interface resize direction to the Windows SC_SIZE edge value.
internal static class WindowDragPolicy
{
    internal static int ResizeEdge(string? direction) => direction switch
    {
        "West" => 1, "East" => 2, "North" => 3, "NorthWest" => 4,
        "NorthEast" => 5, "South" => 6, "SouthWest" => 7, "SouthEast" => 8,
        _ => throw new InvalidOperationException("Unsupported resize direction.")
    };
}
