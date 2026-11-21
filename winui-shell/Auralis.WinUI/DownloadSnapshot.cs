using System.Text.Json;
using System.Text.Json.Serialization;

namespace Auralis.WinUI;

/// The narrow list response from the existing downloader. A null size means
/// progress is unknown; it must not be presented as a measured zero percent.
internal sealed record DownloadEntry
{
    public DownloadEntry() { }
    [JsonPropertyName("id")] public ulong Id { get; init; }
    [JsonPropertyName("file")] public string File { get; init; } = "";
    [JsonPropertyName("status")] public string Status { get; init; } = "";
    [JsonPropertyName("size")] public ulong? Size { get; init; }
    [JsonPropertyName("downloaded")] public ulong Downloaded { get; init; }
    [JsonPropertyName("speed")] public ulong Speed { get; init; }
    [JsonPropertyName("category")] public string Category { get; init; } = "";
    [JsonPropertyName("error")] public string? Error { get; init; }
    public double? Progress => Size is > 0 ? Math.Clamp(100d * Downloaded / Size.Value, 0, 100)
        : Status == "Complete" ? 100 : null;
}

internal sealed record DownloadSnapshot
{
    public DownloadSnapshot() { }
    [JsonPropertyName("downloads")] public List<DownloadEntry> Downloads { get; init; } = new();
    [JsonPropertyName("speed")] public ulong Speed { get; init; }

    internal static DownloadSnapshot FromJson(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty("downloads", out var items) || items.ValueKind != JsonValueKind.Array)
            throw new JsonException("The downloader did not provide a valid download list.");
        return value.Deserialize<DownloadSnapshot>() ?? throw new JsonException("Invalid download list.");
    }
}
