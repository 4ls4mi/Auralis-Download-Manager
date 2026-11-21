namespace Auralis.WinUI;

internal static class WindowRoutePolicy
{
    // Open the actual packaged entry point; the WebView virtual host does not
    // need to guess a default document when a query-only route is requested.
    internal static string InterfaceUrl(string route)
    {
        if (!route.StartsWith("/?",StringComparison.Ordinal) || route.Contains('\\'))
            throw new InvalidOperationException("Invalid interface route.");
        return BridgeMessage.TrustedOrigin + "/index.html" + route[1..];
    }
}
