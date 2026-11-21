using Microsoft.Win32;
namespace Auralis.WinUI;
/// Explicit opt-in for the isolated preview; never edits the released app's entry.
internal static class StartupRegistration
{
    private const string RunKey=@"Software\Microsoft\Windows\CurrentVersion\Run";
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
}
