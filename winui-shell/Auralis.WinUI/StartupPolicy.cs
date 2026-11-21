namespace Auralis.WinUI;
internal static class StartupPolicy
{
    internal const string EntryName="Auralis WinUI Development";
    internal static string Command(string executable)
    {
        if (string.IsNullOrWhiteSpace(executable) || !Path.IsPathFullyQualified(executable) || executable.Contains('"') ||
            !Path.GetFileName(executable).Equals("Auralis.WinUI.exe",StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("The development executable path is invalid.");
        return "\""+executable+"\" --startup";
    }
    internal static bool Owns(string? command,string executable) =>
        command is not null && string.Equals(command,Command(executable),StringComparison.OrdinalIgnoreCase);
}
