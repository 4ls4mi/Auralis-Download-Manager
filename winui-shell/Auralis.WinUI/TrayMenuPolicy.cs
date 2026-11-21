namespace Auralis.WinUI;

internal sealed record TrayMenuEntry(uint Id, string Label, string Action);

internal static class TrayMenuPolicy
{
    internal static readonly TrayMenuEntry[] Entries =
    {
        new(1,"Show Auralis","show"),
        new(3,"Add URL…","add"),
        new(4,"Settings…","settings"),
        new(5,"Start download queue","start_queue"),
        new(6,"Stop download queue","stop_queue"),
        new(2,"Exit Auralis","exit")
    };
}
