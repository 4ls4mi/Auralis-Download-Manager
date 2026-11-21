using Microsoft.UI.Xaml;

namespace Auralis.WinUI;

public partial class App : Application
{
    private MainWindow? _window;
    private NativeUpdateNotifications? _notifications;
    private bool _pendingUpdateActivation;
    private readonly object _activationLock=new();

    public App()
    {
        InitializeComponent();
        try { _notifications=new NativeUpdateNotifications(OnUpdateNotification); }
        catch (Exception) { /* In-app update notices remain available. */ }
    }

    private void OnUpdateNotification()
    {
        MainWindow? window;
        lock (_activationLock)
        {
            window=_window;
            if (window is null) { _pendingUpdateActivation=true; return; }
        }
        window.DispatcherQueue.TryEnqueue(() => window.ShowUpdateFromNotification());
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var main = new MainWindow(_notifications);
        bool pending;
        lock (_activationLock) { _window=main; pending=_pendingUpdateActivation; _pendingUpdateActivation=false; }
        main.Activate();
        _ = main.ApplyStartupPreferencesAsync(Environment.GetCommandLineArgs().Any(arg=>arg.Equals("--startup",StringComparison.OrdinalIgnoreCase)));
        if (pending) main.ShowUpdateFromNotification();
    }
}
