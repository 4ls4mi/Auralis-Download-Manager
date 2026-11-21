namespace Auralis.WinUI;

/// The installed host is opt-in until migration, command parity and Windows
/// validation are complete. Development builds remain isolated by default.
internal static class HostProfile
{
#if AURALIS_INSTALLED_HOST
    internal const bool Installed = true;
#else
    internal const bool Installed = false;
#endif
}
