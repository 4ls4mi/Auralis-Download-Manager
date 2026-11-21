namespace Auralis.WinUI;

internal static class WindowClosePolicy
{
    internal static bool ShouldHide(bool keepInTray, bool trayAvailable, bool forceExit) =>
        !forceExit && keepInTray && trayAvailable;
}
