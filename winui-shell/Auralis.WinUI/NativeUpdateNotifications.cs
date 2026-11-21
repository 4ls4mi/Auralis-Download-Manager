using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Auralis.WinUI;

/// One quiet system notification for the explicit Windows-notification choice.
/// The in-app update notice is owned separately by the interface.
internal sealed class NativeUpdateNotifications : IDisposable
{
    private readonly Action _activate;
    private bool _registered;

    internal NativeUpdateNotifications(Action activate)
    {
        _activate=activate;
        if (!AppNotificationManager.IsSupported()) throw new InvalidOperationException("Windows notifications are unavailable.");
        AppNotificationManager.Default.NotificationInvoked += OnInvoked;
        try { AppNotificationManager.Default.Register(); _registered=true; }
        catch { AppNotificationManager.Default.NotificationInvoked -= OnInvoked; throw; }
    }

    private void OnInvoked(AppNotificationManager sender,AppNotificationActivatedEventArgs args)
    {
        if (args.Arguments.TryGetValue("action",out var action) && action=="show-update") _activate();
    }

    internal void Show(string version)
    {
        if (!_registered || !UpdatePolicy.TryVersion(version,out _)) throw new InvalidOperationException("Invalid update notification.");
        var notification=new AppNotificationBuilder()
            .AddArgument("action","show-update")
            .AddText("Auralis update available")
            .AddText($"Version {version} is ready to review in Auralis.")
            .MuteAudio()
            .BuildNotification();
        AppNotificationManager.Default.Show(notification);
    }

    public void Dispose()
    {
        if (!_registered) return;
        _registered=false;
        AppNotificationManager.Default.NotificationInvoked -= OnInvoked;
        try { AppNotificationManager.Default.Unregister(); }
        catch (Exception) { /* Shutdown must continue if Windows notifications are unavailable. */ }
    }
}
