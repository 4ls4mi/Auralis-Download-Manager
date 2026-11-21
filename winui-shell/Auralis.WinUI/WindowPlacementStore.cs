using System.Text.Json;

namespace Auralis.WinUI;

internal static class WindowPlacementStore
{
    internal static WindowPlacement? Load(string path)
    {
        try
        {
            var file=new FileInfo(path);
            if (!file.Exists || file.Length>8192 || (file.Attributes & FileAttributes.ReparsePoint)!=0) return null;
            var state=JsonSerializer.Deserialize<WindowPlacement>(File.ReadAllText(path));
            return WindowPlacementPolicy.Valid(state) ? state : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or NotSupportedException) { return null; }
    }

    internal static void Save(string path, WindowPlacement state)
    {
        if (!WindowPlacementPolicy.Valid(state)) throw new ArgumentException("Invalid window placement.");
        string folder=Path.GetDirectoryName(path) ?? throw new ArgumentException("Invalid placement path.");
        LocalWebviewBridge.EnsureDevelopmentDirectory(folder);
        if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint)!=0)
            throw new IOException("The placement file cannot be a link.");
        string temporary=Path.Combine(folder,"placement-"+Guid.NewGuid().ToString("N")+".tmp");
        try
        {
            File.WriteAllText(temporary,JsonSerializer.Serialize(state));
            File.Move(temporary,path,overwrite:true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
