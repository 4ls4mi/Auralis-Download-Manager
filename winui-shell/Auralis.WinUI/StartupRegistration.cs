using Microsoft.Win32;
using System.Text.Json;
namespace Auralis.WinUI;
/// Explicit opt-in for the isolated preview; never edits the released app's entry.
internal static class StartupRegistration
{
    private const string RunKey=@"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string InstalledEntry="Auralis Download Manager";
    private const string StartMinimized="--auralis-startup-minimized";
    private const string StartWindow="--auralis-startup-window";
    private static string Executable() => Environment.ProcessPath ?? throw new InvalidOperationException("The preview executable path is unavailable.");
    internal static bool IsEnabled()
    {
        using var key=Registry.CurrentUser.OpenSubKey(RunKey,writable:false);
        var value=key?.GetValue(StartupPolicy.EntryName) as string;
        return StartupPolicy.Owns(value,Executable());
    }
    internal static void SetEnabled(bool enabled)
    {
        string executable=Executable();
        string command=StartupPolicy.Command(executable);
        using var key=Registry.CurrentUser.CreateSubKey(RunKey,writable:true) ?? throw new InvalidOperationException("The Windows startup settings are unavailable.");
        var old=key.GetValue(StartupPolicy.EntryName);
        if (old is not null && (old is not string text || !StartupPolicy.Owns(text,executable)))
            throw new InvalidOperationException("Another development preview is registered for startup. Disable it from that copy before changing this setting.");
        if (enabled) key.SetValue(StartupPolicy.EntryName,command,RegistryValueKind.String);
        else if (old is not null) key.DeleteValue(StartupPolicy.EntryName,throwOnMissingValue:false);
    }

    private static string InstalledConfigPath()
    {
        string basePath=Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (!Path.IsPathFullyQualified(basePath)) throw new InvalidOperationException("The settings directory is unavailable.");
        return Path.Combine(basePath,"com.misterhybrid.glass","startup.json");
    }

    internal static JsonElement InstalledSettings()
    {
        using var key=Registry.CurrentUser.OpenSubKey(RunKey,writable:false);
        string? command=key?.GetValue(InstalledEntry) as string;
        string mode=command?.EndsWith(StartWindow,StringComparison.OrdinalIgnoreCase)==true ? "window" :
                    command?.EndsWith(StartMinimized,StringComparison.OrdinalIgnoreCase)==true ? "minimized" : ReadSavedMode();
        return JsonSerializer.SerializeToElement(new { enabled=command is not null, mode });
    }

    private static string ReadSavedMode()
    {
        try
        {
            using var value=JsonDocument.Parse(File.ReadAllText(InstalledConfigPath()));
            if (value.RootElement.TryGetProperty("mode",out var mode) && mode.GetString() is string text && text is "window" or "minimized") return text;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException) { }
        return "minimized";
    }

    internal static JsonElement SetInstalledSettings(bool enabled,string mode)
    {
        if (mode is not ("window" or "minimized")) throw new InvalidOperationException("Unsupported startup mode.");
        string exe=Environment.ProcessPath ?? throw new InvalidOperationException("The application path is unavailable.");
        if (!Path.IsPathFullyQualified(exe) || exe.Contains('"')) throw new InvalidOperationException("The application path is unavailable.");
        string command=$"\"{exe}\" {(mode=="minimized" ? StartMinimized : StartWindow)}";
        string config=InstalledConfigPath();
        Directory.CreateDirectory(Path.GetDirectoryName(config)!);
        // Keep the file compatible with the existing Auralis settings, so the
        // chosen mode survives switching startup off and back on.
        File.WriteAllText(config,JsonSerializer.Serialize(new { enabled, mode }));
        using var key=Registry.CurrentUser.CreateSubKey(RunKey,writable:true) ?? throw new InvalidOperationException("Windows startup settings are unavailable.");
        if (enabled) key.SetValue(InstalledEntry,command,RegistryValueKind.String);
        else key.DeleteValue(InstalledEntry,throwOnMissingValue:false);
        return JsonSerializer.SerializeToElement(new { enabled, mode });
    }
}
